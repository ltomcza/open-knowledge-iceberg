```python
def upsert(
    self,
    df: pa.Table,
    join_cols: list[str] | None = None,
    when_matched_update_all: bool = True,
    when_not_matched_insert_all: bool = True,
    case_sensitive: bool = True,
    branch: str | None = MAIN_BRANCH,
    snapshot_properties: dict[str, str] = EMPTY_DICT,
) -> UpsertResult:
```