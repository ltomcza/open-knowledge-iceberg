---
type: PyIceberg Guide
title: PyIceberg — Expression DSL and Row Filter Syntax
description: The two ways to filter rows in PyIceberg scans — the composable Python Expression DSL (EqualTo, And, Or, ...) and the SQL-like string row-filter syntax — and when to use each.
aliases: [pyiceberg row_filter, pyiceberg expression dsl, pyiceberg EqualTo, pyiceberg And Or Not, pyiceberg string filter, pyiceberg WHERE clause, BooleanExpression]
tags: [pyiceberg, python, expressions, filters, row-filter, dsl]
timestamp: 2026-07-31T00:00:00Z
resource: https://py.iceberg.apache.org/expression-dsl
---

# Retrieval Notes

Read this first for "how do I write a filter for a PyIceberg scan", "EqualTo vs
string filter", or "PyIceberg WHERE clause syntax". Both forms feed into the
`row_filter` argument covered in [reading-tables.md](reading-tables.md); the
Expression DSL objects are also used for `overwrite_filter` and `delete_filter`
in [writing-and-upsert.md](writing-and-upsert.md).

# Summary

- Two interchangeable ways to build a `row_filter`: the type-safe **Expression
  DSL** (`EqualTo("age", 18)`, `And(...)`, `Or(...)`, `Not(...)`) or a **SQL-like
  string** (`"age = 18"`).
  Both compile to the same underlying `BooleanExpression`.
- Use the string syntax for quick, readable, ad-hoc filters (especially when
  building queries dynamically as text); use the Expression DSL for
  programmatically composed or reusable filter logic where type safety and
  IDE autocompletion matter.
- `IsNull`/`IsNaN` on a **required** field is always optimized to `False`;
  `NotNull`/`NotNaN` on a required field is always optimized to `True`.
- In the string syntax, `==` is an alias for `=`, `<>` is an alias for `!=`.
- String literals must use **single quotes**; double quotes are reserved for
  column identifiers (e.g. `"my.column"`).
- The `LIKE` wildcard `%` is only valid at the **end** of the pattern — leading
  or embedded `%` raises an error.
- Operator precedence in the string syntax: `NOT` > `AND` > `OR`; use
  parentheses for clarity.

# Expression DSL

Import predicates and combinators from `pyiceberg.expressions`.

## Terms

```python
from pyiceberg.expressions import Reference

age_field = Reference("age")
```

## Literal Predicates

```python
from pyiceberg.expressions import EqualTo, NotEqualTo, LessThan, LessThanOrEqual, GreaterThan, GreaterThanOrEqual

EqualTo("age", 18)
NotEqualTo("age", 18)
LessThan("age", 18)
LessThanOrEqual("age", 18)
GreaterThan("age", 18)
GreaterThanOrEqual("age", 18)
```

## Set Predicates

```python
from pyiceberg.expressions import In, NotIn

In("age", [18, 19, 20])
NotIn("age", [18, 19, 20])
```

## Unary Predicates

```python
from pyiceberg.expressions import IsNull, NotNull

IsNull("name")
NotNull("name")
```

## String Predicates

```python
from pyiceberg.expressions import StartsWith, NotStartsWith

StartsWith("name", "John")      # True for 'Johnathan', False for 'Johan'
NotStartsWith("name", "John")   # False for 'Johnathan', True for 'Johan'
```

## Logical Operators

```python
from pyiceberg.expressions import And, Or, Not

And(GreaterThanOrEqual("age", 18), LessThanOrEqual("age", 65))
Or(LessThan("age", 18), GreaterThan("age", 65))
Not(GreaterThanOrEqual("age", 18))
```

## Complex Expressions

```python
from pyiceberg.expressions import And, Or, Not, EqualTo, GreaterThan, LessThan, In

complex_filter = And(
    And(
        GreaterThanOrEqual("age", 18),
        LessThanOrEqual("age", 65)
    ),
    Or(
        EqualTo("status", "active"),
        EqualTo("status", "pending")
    )
)

age_in_range = Not(
    Or(LessThan("age", 18), GreaterThan("age", 65))
)
```

Break large expressions into named sub-expressions for readability:

```python
age_range = And(GreaterThanOrEqual("age", 18), LessThanOrEqual("age", 65))
status_filter = Or(EqualTo("status", "active"), EqualTo("status", "pending"))
complex_filter = And(age_range, status_filter)
```

## Common Pitfalls

- `IsNull`/`IsNaN` on a required field always evaluates to `False`;
  `NotNull`/`NotNaN` on a required field always evaluates to `True` — the DSL
  optimizes these automatically, which can be surprising if you expected the
  predicate to be evaluated per-row.
- `StartsWith`/`NotStartsWith` require the field to actually be a string type.

# Row Filter Syntax (SQL-like strings)

Used the same place as Expression DSL objects: `table.scan(row_filter="...")`.

## Column References

```
column_name
"column.name"      -- quoted identifier, needed for names with special chars
```

## Literals

- Strings: `'hello world'`
- Numbers: `42`, `-42`, `3.14`
- Booleans: `true`, `false` (case-insensitive)

## Comparisons

```
column = 42
column != 42        -- or column <> 42
column > 42
column >= 42
column < 42
column <= 42
column == 42        -- == is an alias for =
```

## NULL / NaN Checks

```
column IS NULL
column IS NOT NULL
column IS NAN
column IS NOT NAN
```

## IN / NOT IN

```
column IN ('a', 'b', 'c')
column NOT IN (1, 2, 3)
```

## LIKE

```
column LIKE 'prefix%'
column NOT LIKE 'prefix%'
```

The `%` wildcard is **only** supported at the end of the pattern — `'%prefix'` or
`'%mid%'` raises an error.

## BETWEEN

Inclusive range, equivalent to `a >= x AND a <= y`:

```
column BETWEEN 1 AND 2
column BETWEEN 1.0 AND 2.0
column BETWEEN '2025-01-01' AND '2025-01-02'
column BETWEEN '2025-01-01T00:00:00.000000' AND '2025-01-02T12:00:00.000000'
```

## Logical Operations

```
column1 = 42 AND column2 = 'hello'
column1 > 0 OR column2 IS NULL
NOT (column1 = 42)
(column1 = 42 AND column2 = 'hello') OR column3 IS NULL
```

## Complete Examples

```
status = 'active' AND age > 18 AND NOT (country IN ('US', 'CA'))

name LIKE 'John%' AND age >= 21

price IS NOT NULL AND price > 100 AND quantity > 0

(status = 'pending' OR status = 'processing') AND NOT (priority = 'low')
```

## Common Pitfalls

| Pitfall | Wrong | Right |
|---|---|---|
| Double-quoting string literals | `name = "John"` | `name = 'John'` (double quotes are for column identifiers) |
| Wildcard in middle/start | `name LIKE '%John%'` | `name LIKE 'John%'` |
| Assuming string case-insensitivity | `status = 'Active'` won't match `'active'` | Match case exactly; only booleans are case-insensitive |

# Citations

[1] [PyIceberg — Expression DSL](https://py.iceberg.apache.org/expression-dsl)
[2] [PyIceberg — Row Filter Syntax](https://py.iceberg.apache.org/row-filter-syntax)
