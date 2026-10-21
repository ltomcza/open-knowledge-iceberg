[Skip to content](https://py.iceberg.apache.org/row-filter-syntax/#row-filter-syntax)

# Row Filter Syntax [¶](https://py.iceberg.apache.org/row-filter-syntax/\#row-filter-syntax "Permanent link")

In addition to the primary [Expression DSL](https://py.iceberg.apache.org/expression-dsl/), PyIceberg provides a string-based statement interface for filtering rows in Iceberg tables. This guide explains the syntax and provides examples for supported operations.

The row filter syntax is designed to be similar to SQL WHERE clauses. Here are the basic components:

## Column References [¶](https://py.iceberg.apache.org/row-filter-syntax/\#column-references "Permanent link")

Columns can be referenced using either unquoted or quoted identifiers:

```
column_name
"column.name"
```

## Literals [¶](https://py.iceberg.apache.org/row-filter-syntax/\#literals "Permanent link")

The following literal types are supported:

- Strings: `'hello world'`
- Numbers: `42`, `-42`, `3.14`
- Booleans: `true`, `false` (case insensitive)

## Comparison Operations [¶](https://py.iceberg.apache.org/row-filter-syntax/\#comparison-operations "Permanent link")

### Basic Comparisons [¶](https://py.iceberg.apache.org/row-filter-syntax/\#basic-comparisons "Permanent link")

```
column = 42
column != 42
column > 42
column >= 42
column < 42
column <= 42
```

Note

The `==` operator is an alias for `=` and `<>` is an alias for `!=`

### String Comparisons [¶](https://py.iceberg.apache.org/row-filter-syntax/\#string-comparisons "Permanent link")

```
column = 'hello'
column != 'world'
```

## NULL Checks [¶](https://py.iceberg.apache.org/row-filter-syntax/\#null-checks "Permanent link")

Check for NULL values using the `IS NULL` and `IS NOT NULL` operators:

```
column IS NULL
column IS NOT NULL
```

## NaN Checks [¶](https://py.iceberg.apache.org/row-filter-syntax/\#nan-checks "Permanent link")

For floating-point columns, you can check for NaN values:

```
column IS NAN
column IS NOT NAN
```

## IN and NOT IN [¶](https://py.iceberg.apache.org/row-filter-syntax/\#in-and-not-in "Permanent link")

Check if a value is in a set of values:

```
column IN ('a', 'b', 'c')
column NOT IN (1, 2, 3)
```

## LIKE Operations [¶](https://py.iceberg.apache.org/row-filter-syntax/\#like-operations "Permanent link")

The LIKE operator supports pattern matching with a wildcard `%` at the end of the string:

```
column LIKE 'prefix%'
column NOT LIKE 'prefix%'
```

Important

The `%` wildcard is only supported at the end of the pattern. Using it in the middle or beginning of the pattern will raise an error.

## BETWEEN [¶](https://py.iceberg.apache.org/row-filter-syntax/\#between "Permanent link")

The BETWEEN operator filters a column against an inclusive range of two comparable literals, e.g. `a between 1 and 2` is equivalent to `a >= 1 and a <= 2`.

```
column BETWEEN 1 AND 2
column BETWEEN 1.0 AND 2.0
column BETWEEN '2025-01-01' AND '2025-01-02'
column BETWEEN '2025-01-01T00:00:00.000000' AND '2025-01-02T12:00:00.000000'
```

## Logical Operations [¶](https://py.iceberg.apache.org/row-filter-syntax/\#logical-operations "Permanent link")

Combine multiple conditions using logical operators:

```
column1 = 42 AND column2 = 'hello'
column1 > 0 OR column2 IS NULL
NOT (column1 = 42)
```

Tip

Parentheses can be used to group logical operations for clarity:

```
(column1 = 42 AND column2 = 'hello') OR column3 IS NULL
```

## Complete Examples [¶](https://py.iceberg.apache.org/row-filter-syntax/\#complete-examples "Permanent link")

Here are some complete examples showing how to combine different operations:

```
-- Complex filter with multiple conditions
status = 'active' AND age > 18 AND NOT (country IN ('US', 'CA'))

-- Filter with string pattern matching
name LIKE 'John%' AND age >= 21

-- Filter with NULL checks and numeric comparisons
price IS NOT NULL AND price > 100 AND quantity > 0

-- Filter with multiple logical operations
(status = 'pending' OR status = 'processing') AND NOT (priority = 'low')
```

## Common Pitfalls [¶](https://py.iceberg.apache.org/row-filter-syntax/\#common-pitfalls "Permanent link")

1. **String Quoting**: Always use single quotes for string literals. Double quotes are reserved for column identifiers.

```
-- Correct
name = 'John'

-- Incorrect
name = "John"
```

1. **Wildcard Usage**: The `%` wildcard in LIKE patterns can only appear at the end.

```
-- Correct
name LIKE 'John%'

-- Incorrect (will raise an error)
name LIKE '%John%'
```

1. **Case Sensitivity**: Boolean literals (`true`/`false`) are case insensitive, but string comparisons are case sensitive.

```
-- All valid
is_active = true
is_active = TRUE
is_active = True

-- Case sensitive
status = 'Active'  -- Will not match 'active'
```

## Best Practices [¶](https://py.iceberg.apache.org/row-filter-syntax/\#best-practices "Permanent link")

1. For complex use cases, use the primary [Expression DSL](https://py.iceberg.apache.org/expression-dsl/)
2. When using multiple conditions, consider the order of operations (NOT > AND > OR)
3. For string comparisons, be consistent with case usage

Back to top