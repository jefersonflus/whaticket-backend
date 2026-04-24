import { QueryInterface } from "sequelize";
import { hash } from "bcryptjs";

module.exports = {
  up: (queryInterface: QueryInterface) => {
    return queryInterface.sequelize.transaction(async t => {
      const adminEmail = process.env.SEED_ADMIN_EMAIL || "admin@admin.com";
      const adminPassword = process.env.SEED_ADMIN_PASSWORD || "123456";
      const passwordHash = await hash(adminPassword, 8);
      return Promise.all([
        queryInterface.bulkInsert(
          "Users",
          [
            {
              name: process.env.SEED_ADMIN_NAME || "Admin",
              email: adminEmail,
              profile: "admin",
              passwordHash,
              companyId: 1,
              createdAt: new Date(),
              updatedAt: new Date(),
              super: true
            }
          ],
          { transaction: t }
        )
      ]);
    });
  },

  down: async (queryInterface: QueryInterface) => {
    return queryInterface.bulkDelete("Users", {});
  }
};
