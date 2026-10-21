[Skip to content](https://py.iceberg.apache.org/expression-dsl/#expression-dsl)

# Expression DSL [¶](https://py.iceberg.apache.org/expression-dsl/\#expression-dsl "Permanent link")

The PyIceberg library provides a powerful expression Domain Specific Language (DSL) for building complex row filter expressions. This guide will help you understand how to use the expression DSL effectively. This DSL allows you to build type-safe expressions for use in the `row_filter` scan argument.

They are composed of terms, predicates, and logical operators.

## Basic Concepts [¶](https://py.iceberg.apache.org/expression-dsl/\#basic-concepts "Permanent link")

### Terms [¶](https://py.iceberg.apache.org/expression-dsl/\#terms "Permanent link")

Terms are the basic building blocks of expressions. They represent references to fields in your data:

```
from pyiceberg.expressions import Reference

# Create a reference to a field named "age"
age_field = Reference("age")
```

### Predicates [¶](https://py.iceberg.apache.org/expression-dsl/\#predicates "Permanent link")

Predicates are expressions that evaluate to a boolean value. They can be combined using logical operators.

#### Literal Predicates [¶](https://py.iceberg.apache.org/expression-dsl/\#literal-predicates "Permanent link")

```
from pyiceberg.expressions import EqualTo, NotEqualTo, LessThan, LessThanOrEqual, GreaterThan, GreaterThanOrEqual

# age equals 18
age_equals_18 = EqualTo("age", 18)

# age is not equal to 18
age_not_equals_18 = NotEqualTo("age", 18)

# age is less than 18
age_less_than_18 = LessThan("age", 18)

# Less than or equal to
age_less_than_or_equal_18 = LessThanOrEqual("age", 18)

# Greater than
age_greater_than_18 = GreaterThan("age", 18)

# Greater than or equal to
age_greater_than_or_equal_18 = GreaterThanOrEqual("age", 18)
```

#### Set Predicates [¶](https://py.iceberg.apache.org/expression-dsl/\#set-predicates "Permanent link")

```
from pyiceberg.expressions import In, NotIn

# age is one of 18, 19, 20
age_in_set = In("age", [18, 19, 20])

# age is not 18, 19, oer 20
age_not_in_set = NotIn("age", [18, 19, 20])
```

#### Unary Predicates [¶](https://py.iceberg.apache.org/expression-dsl/\#unary-predicates "Permanent link")

```
from pyiceberg.expressions import IsNull, NotNull

# Is null
name_is_null = IsNull("name")

# Is not null
name_is_not_null = NotNull("name")
```

#### String Predicates [¶](https://py.iceberg.apache.org/expression-dsl/\#string-predicates "Permanent link")

```
from pyiceberg.expressions import StartsWith, NotStartsWith

# TRUE for 'Johnathan', FALSE for 'Johan'
name_starts_with = StartsWith("name", "John")

# FALSE for 'Johnathan', TRUE for 'Johan'
name_not_starts_with = NotStartsWith("name", "John")
```

### Logical Operators [¶](https://py.iceberg.apache.org/expression-dsl/\#logical-operators "Permanent link")

You can combine predicates using logical operators:

```
from pyiceberg.expressions import And, Or, Not

# TRUE for 25, FALSE for 67 and 15
age_between = And(
    GreaterThanOrEqual("age", 18),
    LessThanOrEqual("age", 65)
)

# FALSE for 25, TRUE for 67 and 15
age_outside = Or(
    LessThan("age", 18),
    GreaterThan("age", 65)
)

# NOT operator
not_adult = Not(GreaterThanOrEqual("age", 18))
```

## Advanced Usage [¶](https://py.iceberg.apache.org/expression-dsl/\#advanced-usage "Permanent link")

### Complex Expressions [¶](https://py.iceberg.apache.org/expression-dsl/\#complex-expressions "Permanent link")

You can build complex expressions by combining multiple predicates and operators:

```
from pyiceberg.expressions import And, Or, Not, EqualTo, GreaterThan, LessThan, In

# (age >= 18 AND age <= 65) AND (status = 'active' OR status = 'pending')
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

# NOT (age < 18 OR age > 65)
age_in_range = Not(
    Or(
        LessThan("age", 18),
        GreaterThan("age", 65)
    )
)
```

## Best Practices [¶](https://py.iceberg.apache.org/expression-dsl/\#best-practices "Permanent link")

1. **Use Type Hints**: Always use type hints when working with expressions to catch type-related errors early.

2. **Break Down Complex Expressions**: For complex expressions, break them down into smaller, more manageable parts:


```
# Instead of this:
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

# Do this:
age_range = And(
    GreaterThanOrEqual("age", 18),
    LessThanOrEqual("age", 65)
)

status_filter = Or(
    EqualTo("status", "active"),
    EqualTo("status", "pending")
)

complex_filter = And(age_range, status_filter)
```

## Common Pitfalls [¶](https://py.iceberg.apache.org/expression-dsl/\#common-pitfalls "Permanent link")

1. **Null Handling**: Be careful when using `IsNull` and `NotNull` predicates with required fields. The expression DSL will automatically optimize these cases:
2. `IsNull` (and `IsNaN` for doubles/floats) on a required field will always return `False`
3. `NotNull` (and `NotNaN` for doubles/floats) on a required field will always return `True`

4. **String Comparisons**: When using string predicates like `StartsWith`, ensure that the field type is a string type.


## Examples [¶](https://py.iceberg.apache.org/expression-dsl/\#examples "Permanent link")

Here are some practical examples of using the expression DSL:

### Basic Filtering [¶](https://py.iceberg.apache.org/expression-dsl/\#basic-filtering "Permanent link")

```
from datetime import datetime
from pyiceberg.expressions import (
    And,
    EqualTo,
    GreaterThanOrEqual,
    LessThanOrEqual,
    GreaterThan,
    In
)

active_adult_users_filter = And(
    EqualTo("status", "active"),
    GreaterThanOrEqual("age", 18)
)

high_value_customers = And(
    GreaterThan("total_spent", 1000),
    In("membership_level", ["gold", "platinum"])
)

date_range_filter = And(
    GreaterThanOrEqual("created_at", datetime(2024, 1, 1)),
    LessThanOrEqual("created_at", datetime(2024, 12, 31))
)
```

### Multi-Condition Filter [¶](https://py.iceberg.apache.org/expression-dsl/\#multi-condition-filter "Permanent link")

```
from pyiceberg.expressions import And, Or, Not, EqualTo, GreaterThan

complex_filter = And(
    Not(EqualTo("status", "deleted")),
    Or(
        And(
            EqualTo("type", "premium"),
            GreaterThan("subscription_months", 12)
        ),
        EqualTo("type", "enterprise")
    )
)
```

Back to top