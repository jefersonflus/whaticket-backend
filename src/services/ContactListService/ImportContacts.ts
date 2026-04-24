import fs from "fs";
import path from "path";
import { execFileSync } from "child_process";
import ContactListItem from "../../models/ContactListItem";
import CheckContactNumber from "../WbotServices/CheckNumber";
import { logger } from "../../utils/logger";
import uploadConfig from "../../config/upload";
import AppError from "../../errors/AppError";

const MAX_IMPORT_ROWS = Number(process.env.CONTACT_LIST_IMPORT_MAX_ROWS || "10000");
const MAX_IMPORT_FILE_SIZE_MB = Number(
  process.env.CONTACT_LIST_IMPORT_MAX_SIZE_MB || "5"
);
const MAX_IMPORT_FILE_SIZE_BYTES = Math.max(1, MAX_IMPORT_FILE_SIZE_MB) * 1024 * 1024;
const XLSX_PARSE_TIMEOUT_MS = Number(
  process.env.CONTACT_LIST_IMPORT_XLSX_TIMEOUT_MS || "15000"
);
const CONTACT_IMPORT_ALLOW_XLSX =
  String(process.env.CONTACT_LIST_IMPORT_ALLOW_XLSX || "true").toLowerCase() ===
  "true";

const ALLOWED_EXTENSIONS = new Set([".csv", ".xls", ".xlsx"]);

const normalizeHeader = (value: string) =>
  String(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");

const pickField = (
  row: Record<string, unknown>,
  aliases: string[]
): string => {
  const entry = Object.keys(row).find(key => {
    const normalized = normalizeHeader(key);
    return aliases.includes(normalized);
  });

  if (!entry) return "";
  const value = row[entry];
  return typeof value === "string" ? value.trim() : String(value || "").trim();
};

const parseSpreadsheetIsolated = (filePath: string): Record<string, unknown>[] => {
  const workerScript = `
const XLSX = require("xlsx");
const filePath = process.argv[1];
const workbook = XLSX.readFile(filePath, { cellFormula: false, dense: true });
const firstSheetName = workbook.SheetNames && workbook.SheetNames[0];
if (!firstSheetName) {
  process.stdout.write("[]");
  process.exit(0);
}
const worksheet = workbook.Sheets[firstSheetName];
const rows = XLSX.utils.sheet_to_json(worksheet, { header: 0, raw: false, defval: "" });
process.stdout.write(JSON.stringify(rows));
`;

  const stdout = execFileSync(
    process.execPath,
    ["--max-old-space-size=192", "-e", workerScript, filePath],
    {
      timeout: XLSX_PARSE_TIMEOUT_MS,
      maxBuffer: 16 * 1024 * 1024,
      encoding: "utf8"
    }
  );

  const parsedRows = JSON.parse(stdout);
  return Array.isArray(parsedRows) ? parsedRows : [];
};

const resolveAndValidateImportFile = (file: Express.Multer.File | undefined) => {
  if (!file) {
    throw new AppError("ERR_CONTACT_IMPORT_FILE_REQUIRED", 400);
  }

  const resolvedPath = path.resolve(file.path || "");
  const uploadBaseDir = path.resolve(uploadConfig.directory);
  const extension = path.extname(file.originalname || resolvedPath).toLowerCase();

  if (!resolvedPath.startsWith(uploadBaseDir)) {
    throw new AppError("ERR_CONTACT_IMPORT_INVALID_PATH", 400);
  }

  if (!ALLOWED_EXTENSIONS.has(extension)) {
    throw new AppError("ERR_CONTACT_IMPORT_INVALID_EXTENSION", 400);
  }

  if ((extension === ".xlsx" || extension === ".xls") && !CONTACT_IMPORT_ALLOW_XLSX) {
    throw new AppError("ERR_CONTACT_IMPORT_XLSX_DISABLED", 400);
  }

  const stats = fs.statSync(resolvedPath);
  if (stats.size > MAX_IMPORT_FILE_SIZE_BYTES) {
    throw new AppError("ERR_CONTACT_IMPORT_FILE_TOO_LARGE", 413);
  }

  return resolvedPath;
};

export async function ImportContacts(
  contactListId: number,
  companyId: number,
  file: Express.Multer.File | undefined
) {
  const resolvedPath = resolveAndValidateImportFile(file);

  let rows: Record<string, unknown>[] = [];
  try {
    rows = parseSpreadsheetIsolated(resolvedPath);
  } catch (error) {
    logger.error(`Falha ao processar planilha de importacao: ${resolvedPath}`);
    logger.error(error);
    throw new AppError("ERR_CONTACT_IMPORT_PARSE_FAILED", 400);
  }

  if (rows.length > MAX_IMPORT_ROWS) {
    throw new AppError("ERR_CONTACT_IMPORT_TOO_MANY_ROWS", 400);
  }

  const contacts = rows
    .map(row => {
      const safeRow =
        row && typeof row === "object" && !Array.isArray(row)
          ? (row as Record<string, unknown>)
          : {};

      const name = pickField(safeRow, ["nome", "name"]);
      const number = pickField(safeRow, ["numero", "number", "telefone", "phone"]).replace(
        /\D/g,
        ""
      );
      const email = pickField(safeRow, ["email", "mail"]);

      return { name, number, email, contactListId, companyId };
    })
    .filter(contact => !!contact.number);

  const contactList: ContactListItem[] = [];

  for (const contact of contacts) {
    const [newContact, created] = await ContactListItem.findOrCreate({
      where: {
        number: `${contact.number}`,
        contactListId: contact.contactListId,
        companyId: contact.companyId
      },
      defaults: contact
    });
    if (created) {
      contactList.push(newContact);
    }
  }

  if (contactList) {
    for (let newContact of contactList) {
      try {
        const response = await CheckContactNumber(newContact.number, companyId);
        newContact.isWhatsappValid = response.exists;
        const number = response.jid.replace(/\D/g, "");
        newContact.number = number;
        await newContact.save();
      } catch (e) {
        logger.error(`Número de contato inválido: ${newContact.number}`);
      }
    }
  }

  return contactList;
}
