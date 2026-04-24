import * as Sentry from "@sentry/node";
import { isArray, isString } from "lodash";
import AppError from "../../errors/AppError";
import GetDefaultWhatsApp from "../../helpers/GetDefaultWhatsApp";
import { getWbot } from "../../libs/wbot";
import Contact from "../../models/Contact";
import { logger } from "../../utils/logger";
import ShowBaileysService from "../BaileysServices/ShowBaileysService";
import CreateContactService from "../ContactServices/CreateContactService";

type PhoneContactPayload = {
  id?: string;
  name?: string;
  notify?: string;
};

const formatError = (error: unknown): string => {
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  try {
    return JSON.stringify(error);
  } catch (_) {
    return String(error);
  }
};

const ImportContactsService = async (companyId: number): Promise<void> => {
  const defaultWhatsapp = await GetDefaultWhatsApp(companyId);
  const wbot = getWbot(defaultWhatsapp.id);

  let phoneContacts: unknown;

  try {
    const contactsString = await ShowBaileysService(wbot.id);
    phoneContacts = contactsString?.contacts;
  } catch (err) {
    Sentry.captureException(err);
    logger.error(
      `Could not get whatsapp contacts from phone. Err: ${formatError(err)}`
    );
    throw new AppError("ERR_WAPP_IMPORT_CONTACTS_FETCH_FAILED", 502);
  }

  let phoneContactsList: unknown;
  try {
    phoneContactsList = isString(phoneContacts)
      ? JSON.parse(phoneContacts)
      : phoneContacts;
  } catch (error) {
    Sentry.captureException(error);
    logger.error(
      `Could not parse whatsapp contacts payload. Err: ${formatError(error)}`
    );
    throw new AppError("ERR_WAPP_IMPORT_CONTACTS_INVALID_PAYLOAD", 502);
  }

  if (!isArray(phoneContactsList)) {
    throw new AppError("ERR_WAPP_IMPORT_CONTACTS_INVALID_PAYLOAD", 502);
  }

  for (const payload of phoneContactsList as PhoneContactPayload[]) {
    try {
      const contactId = `${payload.id || ""}`;

      if (!contactId) continue;
      if (contactId === "status@broadcast" || contactId.includes("g.us")) continue;

      const number = contactId.replace(/\D/g, "");
      if (!number) continue;

      const existingContact = await Contact.findOne({
        where: { number, companyId }
      });

      if (existingContact) {
        existingContact.name = payload.name || payload.notify || existingContact.name;
        await existingContact.save();
      } else {
        await CreateContactService({
          number,
          name: payload.name || payload.notify || number,
          companyId
        });
      }
    } catch (error) {
      Sentry.captureException(error);
      logger.warn(`Could not import a whatsapp contact. Err: ${formatError(error)}`);
    }
  }
};

export default ImportContactsService;
