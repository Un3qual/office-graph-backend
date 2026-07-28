## ADDED Requirements

### Requirement: Concrete references are Ash relationships
Every concrete database foreign key owned by an Office Graph Ash resource SHALL
be represented by a corresponding Ash relationship, and stable inverse domain
relationships SHALL be declared on the destination resource.

#### Scenario: Resource has a concrete foreign key
- **WHEN** a resource column references one concrete destination table
- **THEN** the resource MUST declare a `belongs_to` relationship with matching source and destination attributes

#### Scenario: Identifier is intentionally polymorphic
- **WHEN** a subject, resource, target, or provider identifier can refer to more than one resource type
- **THEN** it MUST NOT be represented as a misleading concrete Ash relationship and MUST have an explicit typed discriminator and validation contract

#### Scenario: Owning resource exposes a stable inverse
- **WHEN** a destination owns a stable collection or one-to-one association
- **THEN** it MUST declare the corresponding `has_many` or `has_one` relationship so callers do not rebuild the association manually

### Requirement: Belongs-to relationships own ordinary foreign-key attributes
Office Graph resources SHALL use the attribute implied by `belongs_to` for
ordinary foreign keys instead of separately declaring the same attribute.

#### Scenario: Ordinary belongs-to relationship is declared
- **WHEN** a relationship uses the conventional or explicitly named source attribute
- **THEN** the relationship MUST define that attribute with the required type, nilability, writability, and visibility

#### Scenario: Explicit source attribute is retained
- **WHEN** `define_attribute? false` is required for a shared, nonstandard, or polymorphic source attribute
- **THEN** architecture conformance MUST record the exact resource, relationship, and reason

### Requirement: Resource declarations are grouped by responsibility
Ash resource files SHALL group identity and scope, lifecycle, domain data, and
timestamp attributes coherently and SHALL keep relationship, action, identity,
policy, and API declarations in a consistent readable order.

#### Scenario: Resource schema changes
- **WHEN** attributes or relationships are added or removed
- **THEN** the complete resource declaration MUST remain grouped by domain responsibility rather than append order

### Requirement: Value objects own their behavior
Struct and value-object modules SHALL own their construction, normalization,
and validation behavior when such behavior exists, while genuinely passive
boundary DTOs MAY remain data-only.

#### Scenario: Consumer normalizes a value object
- **WHEN** multiple consumers construct, normalize, or validate the same struct
- **THEN** that behavior MUST move to the struct's module and consumers MUST use its public function

#### Scenario: Struct is a passive boundary DTO
- **WHEN** a struct only names fields crossing a stable boundary and has no reusable invariant or transformation
- **THEN** it MAY remain data-only and MUST live in the responsibility-based folder for that boundary

### Requirement: Resource conventions are structurally enforced
Canonical backend verification SHALL inspect compiled Ash metadata and the
schema inventory for incomplete relationships, redundant belongs-to
attributes, generic map fields, generic tombstones, and non-database-generated
primary-key defaults.

#### Scenario: Resource convention regresses
- **WHEN** a resource introduces an unmodeled concrete foreign key, a redundant manual belongs-to attribute, a generic map field, a generic tombstone, or an application UUID default
- **THEN** canonical verification MUST fail with the resource and offending declaration
