import "sequelize";
import "sequelize-typescript";

declare module "sequelize" {
  abstract class Model<TModelAttributes extends {} = any, TCreationAttributes extends {} = TModelAttributes> {
    static findByPk(identifier: any, options?: any): Promise<any>;
    static findOne(options?: any): Promise<any>;
    static findAll(options?: any): Promise<any[]>;
    static findOrCreate(options: any): Promise<[any, boolean]>;
    static findAndCountAll(options?: any): Promise<{ rows: any[]; count: any }>;
    static count(options?: any): Promise<any>;
    static create(values?: any, options?: any): Promise<any>;
    static update(values: any, options: any): Promise<any>;
    static destroy(options?: any): Promise<any>;
    static bulkCreate(records: ReadonlyArray<any>, options?: any): Promise<any[]>;
    static upsert(values: any, options?: any): Promise<any>;

    update(values: any, options?: any): Promise<this>;
    reload(options?: any): Promise<this>;
    save(options?: any): Promise<this>;
    destroy(options?: any): Promise<void>;
    getDataValue(key: any): any;
    setDataValue(key: any, value: any): void;
  }

  interface QueryInterface {
    addConstraint(tableName: any, options: any, rawTablename?: any): Promise<void>;
    removeConstraint(tableName: any, constraintName: any, options?: any): Promise<void>;
    addIndex(tableName: any, attributes: any, options?: any): Promise<any>;
    removeIndex(tableName: any, indexNameOrAttributes: any, options?: any): Promise<any>;
  }
}

declare module "sequelize-typescript" {
  interface Model<TModelAttributes extends {} = any, TCreationAttributes extends {} = TModelAttributes> {
    $set(propertyKey: string, values: any, options?: any): Promise<any>;
    $add(propertyKey: string, values: any, options?: any): Promise<any>;
    $get(propertyKey: string, options?: any): Promise<any>;
    $count(propertyKey: string, options?: any): Promise<number>;
  }

  function BelongsTo(associatedClassGetter: any, options?: any): Function;
  function HasMany(associatedClassGetter: any, options?: any): Function;
  function HasOne(associatedClassGetter: any, options?: any): Function;
  function BelongsToMany(associatedClassGetter: any, through: any, foreignKey?: any, otherKey?: any): Function;
  function ForeignKey(relatedClassGetter: any): Function;
}
