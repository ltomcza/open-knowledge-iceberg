[Skip to content](https://py.iceberg.apache.org/reference/pyiceberg/table/maintenance/#pyiceberg.table.maintenance)

# maintenance

## `MaintenanceTable` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/maintenance/\#pyiceberg.table.maintenance.MaintenanceTable "Permanent link")

Source code in `pyiceberg/table/maintenance.py`

|     |     |
| --- | --- |
| ```<br>30<br>31<br>32<br>33<br>34<br>35<br>36<br>37<br>38<br>39<br>40<br>41<br>42<br>43<br>44<br>45<br>``` | ```<br>class MaintenanceTable:<br>    tbl: Table<br>    def __init__(self, tbl: Table) -> None:<br>        self.tbl = tbl<br>    def expire_snapshots(self) -> ExpireSnapshots:<br>        """Return an ExpireSnapshots builder for snapshot expiration operations.<br>        Returns:<br>            ExpireSnapshots builder for configuring and executing snapshot expiration.<br>        """<br>        from pyiceberg.table import Transaction<br>        from pyiceberg.table.update.snapshot import ExpireSnapshots<br>        return ExpireSnapshots(transaction=Transaction(self.tbl, autocommit=True))<br>``` |

### `expire_snapshots()` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/maintenance/\#pyiceberg.table.maintenance.MaintenanceTable.expire_snapshots "Permanent link")

Return an ExpireSnapshots builder for snapshot expiration operations.

Returns:

| Type | Description |
| --- | --- |
| `ExpireSnapshots` | ExpireSnapshots builder for configuring and executing snapshot expiration. |

Source code in `pyiceberg/table/maintenance.py`

|     |     |
| --- | --- |
| ```<br>36<br>37<br>38<br>39<br>40<br>41<br>42<br>43<br>44<br>45<br>``` | ```<br>def expire_snapshots(self) -> ExpireSnapshots:<br>    """Return an ExpireSnapshots builder for snapshot expiration operations.<br>    Returns:<br>        ExpireSnapshots builder for configuring and executing snapshot expiration.<br>    """<br>    from pyiceberg.table import Transaction<br>    from pyiceberg.table.update.snapshot import ExpireSnapshots<br>    return ExpireSnapshots(transaction=Transaction(self.tbl, autocommit=True))<br>``` |

Back to top