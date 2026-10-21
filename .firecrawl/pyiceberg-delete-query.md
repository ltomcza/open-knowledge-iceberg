```python
def delete(
    self,
    delete_filter: str | BooleanExpression,
    snapshot_properties: dict[str, str] = EMPTY_DICT,
    case_sensitive: bool = True,
    branch: str | None = MAIN_BRANCH,
) -> None:
```