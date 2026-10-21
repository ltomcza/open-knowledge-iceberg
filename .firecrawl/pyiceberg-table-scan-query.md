```python
def scan(
    self,
    row_filter: str | BooleanExpression = ALWAYS_TRUE,
    selected_fields: tuple[str, ...] = ("*",),
    case_sensitive: bool = True,
    snapshot_id: int | None = None,
    options: Properties = EMPTY_DICT,
    limit: int | None = None,
) -> DataScan:
```