return [=[
module Asdl2Text {

    Spec = (string text) unique
}

module Asdl2Source {

    Spec = (Definition* definitions) unique

    Definition
        = ModuleDef(string name, Definition* definitions)
        | TypeDef(string name, TypeExpr type_expr)

    TypeExpr
        = Product(Field* fields, boolean unique_flag)
        | Sum(Constructor* constructors, Field* attribute_fields)

    Constructor = (string name, Field* fields, boolean unique_flag) unique

    Field = (TypeRef type_ref, Cardinality cardinality, string name) unique

    TypeRef
        = BuiltinTypeRef(string name)
        | UnqualifiedTypeRef(string name)
        | QualifiedTypeRef(string fqname)

    Cardinality
        = ExactlyOne()
        | Optional()
        | Many()
}

module Asdl2Catalog {

    Spec = (
        Scope root_scope,
        Definition* definitions
    ) unique

    Scope = (
        string fqname,
        LookupEntry* lookups
    ) unique

    LookupEntry = (
        string query_name,
        LookupTarget target
    ) unique

    LookupTarget
        = ProductTarget(ProductHeader header)
        | SumTarget(SumHeader header, VariantHeader* variants)

    Definition
        = ModuleDef(string name, string fqname, Scope scope, Definition* definitions)
        | ProductDef(string name, ProductHeader header, Field* fields, boolean unique_flag)
        | SumDef(string name, SumHeader header, Constructor* constructors, Field* attribute_fields)

    Constructor = (
        string name,
        VariantHeader header,
        Field* fields,
        boolean unique_flag
    ) unique

    Field = (TypeRef type_ref, Cardinality cardinality, string name) unique

    TypeRef
        = BuiltinTypeRef(string name)
        | ExternalTypeRef(string fqname)
        | ProductTargetRef(ProductHeader header)
        | SumTargetRef(SumHeader header, VariantHeader* variants)

    Cardinality
        = ExactlyOne()
        | Optional()
        | Many()

    ProductHeader = (
        string fqname,
        number class_id,
        Asdl2Lowered.CtorFamily ctor
    ) unique

    SumHeader = (
        string fqname,
        number family_id
    ) unique

    VariantHeader = (
        string fqname,
        string parent_fqname,
        string kind_name,
        number class_id,
        number family_id,
        number variant_tag,
        Asdl2Lowered.CtorFamily ctor
    ) unique
}

module Asdl2Lowered {

    Schema = (
        Record* records,
        Sum* sums,
        ArenaSlot* arenas,
        CacheSlot* caches
    ) unique

    Record
        = ProductRecord(
            Asdl2Catalog.ProductHeader header,
            CacheRef cache,
            Field* fields
        )
        | VariantRecord(
            Asdl2Catalog.VariantHeader header,
            CacheRef cache,
            Field* fields
        )

    Sum = (
        Asdl2Catalog.SumHeader header,
        Asdl2Catalog.VariantHeader* variants
    ) unique

    Field
        = InlineField(
            string name,
            string type_name,
            string c_name,
            string c_type,
            CheckSpec check
        )
        | HandleScalarField(
            string name,
            string type_name,
            ScalarCardinality cardinality,
            number arena_id,
            string handle_field,
            string handle_ctype,
            CheckSpec check
        )
        | HandleListField(
            string name,
            string type_name,
            number arena_id,
            string handle_field,
            string handle_ctype,
            CheckSpec check
        )

    ArenaSlot
        = ScalarArenaSlot(
            number arena_id,
            CheckSpec target,
            string handle_ctype
        )
        | ListArenaSlot(
            number arena_id,
            CheckSpec target,
            string handle_ctype
        )

    CheckSpec
        = AnyCheck()
        | BuiltinCheck(string name)
        | ExternalCheck(string fqname)
        | ExactClassCheck(string fqname, number class_id)
        | SumFamilyCheck(string fqname, number family_id, number* variant_tags)

    CacheRef
        = NoCacheRef()
        | CacheSlotRef(number cache_id)

    CacheSlot = (
        number cache_id,
        CacheKind kind,
        number key_arity,
        string owner_fqname
    ) unique

    CacheKind
        = SingletonKind()
        | StructuralKind()

    CtorFamily
        = NullaryCtor()
        | ProductCtor(number field_count)
        | VariantCtor(number field_count)

    ScalarCardinality
        = ExactlyOne()
        | Optional()
}

module Asdl2Machine {

    Schema = (
        SchemaGen gen,
        SchemaParam param,
        SchemaState state
    ) unique

    SchemaGen = (
        RecordGen* records
    ) unique

    RecordGen
        = ProductGen(
            string fqname,
            Asdl2Lowered.CtorFamily ctor,
            CacheGen cache
        )
        | VariantGen(
            string fqname,
            string parent_fqname,
            string kind_name,
            Asdl2Lowered.CtorFamily ctor,
            CacheGen cache
        )

    CacheGen
        = NoCache()
        | SingletonCache()
        | StructuralCache(number key_arity)

    SchemaParam = (
        Asdl2Lowered.Record* records,
        Asdl2Lowered.Sum* sums
    ) unique

    SchemaState = (
        Asdl2Lowered.ArenaSlot* arenas,
        Asdl2Lowered.CacheSlot* caches
    ) unique
}

]=]