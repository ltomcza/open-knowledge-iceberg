[Skip to content](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/#pyiceberg.table.update.snapshot)

# snapshot

## `ExpireSnapshots` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ExpireSnapshots "Permanent link")

Bases: `UpdateTableMetadata['ExpireSnapshots']`

Expire snapshots by ID.

Use table.expire\_snapshots().().commit() to run a specific operation.
Use table.expire\_snapshots().().().commit() to run multiple operations.
Pending changes are applied on commit.

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>1035<br>1036<br>1037<br>1038<br>1039<br>1040<br>1041<br>1042<br>1043<br>1044<br>1045<br>1046<br>1047<br>1048<br>1049<br>1050<br>1051<br>1052<br>1053<br>1054<br>1055<br>1056<br>1057<br>1058<br>1059<br>1060<br>1061<br>1062<br>1063<br>1064<br>1065<br>1066<br>1067<br>1068<br>1069<br>1070<br>1071<br>1072<br>1073<br>1074<br>1075<br>1076<br>1077<br>1078<br>1079<br>1080<br>1081<br>1082<br>1083<br>1084<br>1085<br>1086<br>1087<br>1088<br>1089<br>1090<br>1091<br>1092<br>1093<br>1094<br>1095<br>1096<br>1097<br>1098<br>1099<br>1100<br>1101<br>1102<br>1103<br>1104<br>1105<br>1106<br>1107<br>1108<br>1109<br>1110<br>1111<br>1112<br>1113<br>1114<br>1115<br>1116<br>1117<br>1118<br>1119<br>1120<br>1121<br>1122<br>1123<br>1124<br>1125<br>1126<br>1127<br>1128<br>1129<br>1130<br>1131<br>1132<br>1133<br>1134<br>1135<br>1136<br>``` | ```<br>class ExpireSnapshots(UpdateTableMetadata["ExpireSnapshots"]):<br>    """Expire snapshots by ID.<br>    Use table.expire_snapshots().<operation>().commit() to run a specific operation.<br>    Use table.expire_snapshots().<operation-one>().<operation-two>().commit() to run multiple operations.<br>    Pending changes are applied on commit.<br>    """<br>    _updates: tuple[TableUpdate, ...]<br>    _requirements: tuple[TableRequirement, ...]<br>    _snapshot_ids_to_expire: set[int]<br>    def __init__(self, transaction: Transaction) -> None:<br>        super().__init__(transaction)<br>        self._updates = ()<br>        self._requirements = ()<br>        self._snapshot_ids_to_expire = set()<br>    def _commit(self) -> UpdatesAndRequirements:<br>        """<br>        Commit the staged updates and requirements.<br>        This will remove the snapshots with the given IDs, but will always skip protected snapshots (branch/tag heads).<br>        Returns:<br>            Tuple of updates and requirements to be committed,<br>            as required by the calling parent apply functions.<br>        """<br>        # Remove any protected snapshot IDs from the set to expire, just in case<br>        protected_ids = self._get_protected_snapshot_ids()<br>        self._snapshot_ids_to_expire -= protected_ids<br>        update = RemoveSnapshotsUpdate(snapshot_ids=self._snapshot_ids_to_expire)<br>        self._updates += (update,)<br>        return self._updates, self._requirements<br>    def _get_protected_snapshot_ids(self) -> set[int]:<br>        """<br>        Get the IDs of protected snapshots.<br>        These are the HEAD snapshots of all branches and all tagged snapshots.  These ids are to be excluded from expiration.<br>        Returns:<br>            Set of protected snapshot IDs to exclude from expiration.<br>        """<br>        return {<br>            ref.snapshot_id<br>            for ref in self._transaction.table_metadata.refs.values()<br>            if ref.snapshot_ref_type in [SnapshotRefType.TAG, SnapshotRefType.BRANCH]<br>        }<br>    def by_id(self, snapshot_id: int) -> ExpireSnapshots:<br>        """<br>        Expire a snapshot by its ID.<br>        This will mark the snapshot for expiration.<br>        Args:<br>            snapshot_id (int): The ID of the snapshot to expire.<br>        Returns:<br>            This for method chaining.<br>        """<br>        if self._transaction.table_metadata.snapshot_by_id(snapshot_id) is None:<br>            raise ValueError(f"Snapshot with ID {snapshot_id} does not exist.")<br>        if snapshot_id in self._get_protected_snapshot_ids():<br>            raise ValueError(f"Snapshot with ID {snapshot_id} is protected and cannot be expired.")<br>        self._snapshot_ids_to_expire.add(snapshot_id)<br>        return self<br>    def by_ids(self, snapshot_ids: list[int]) -> ExpireSnapshots:<br>        """<br>        Expire multiple snapshots by their IDs.<br>        This will mark the snapshots for expiration.<br>        Args:<br>            snapshot_ids (List[int]): List of snapshot IDs to expire.<br>        Returns:<br>            This for method chaining.<br>        """<br>        for snapshot_id in snapshot_ids:<br>            self.by_id(snapshot_id)<br>        return self<br>    def older_than(self, dt: datetime) -> ExpireSnapshots:<br>        """<br>        Expire all unprotected snapshots with a timestamp older than a given value.<br>        Args:<br>            dt (datetime): Only snapshots with datetime < this value will be expired.<br>        Returns:<br>            This for method chaining.<br>        """<br>        protected_ids = self._get_protected_snapshot_ids()<br>        expire_from = datetime_to_millis(dt)<br>        for snapshot in self._transaction.table_metadata.snapshots:<br>            if snapshot.timestamp_ms < expire_from and snapshot.snapshot_id not in protected_ids:<br>                self._snapshot_ids_to_expire.add(snapshot.snapshot_id)<br>        return self<br>``` |

### `by_id(snapshot_id)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ExpireSnapshots.by_id "Permanent link")

Expire a snapshot by its ID.

This will mark the snapshot for expiration.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `snapshot_id` | `int` | The ID of the snapshot to expire. | _required_ |

Returns:
This for method chaining.

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>1085<br>1086<br>1087<br>1088<br>1089<br>1090<br>1091<br>1092<br>1093<br>1094<br>1095<br>1096<br>1097<br>1098<br>1099<br>1100<br>1101<br>1102<br>1103<br>1104<br>``` | ```<br>def by_id(self, snapshot_id: int) -> ExpireSnapshots:<br>    """<br>    Expire a snapshot by its ID.<br>    This will mark the snapshot for expiration.<br>    Args:<br>        snapshot_id (int): The ID of the snapshot to expire.<br>    Returns:<br>        This for method chaining.<br>    """<br>    if self._transaction.table_metadata.snapshot_by_id(snapshot_id) is None:<br>        raise ValueError(f"Snapshot with ID {snapshot_id} does not exist.")<br>    if snapshot_id in self._get_protected_snapshot_ids():<br>        raise ValueError(f"Snapshot with ID {snapshot_id} is protected and cannot be expired.")<br>    self._snapshot_ids_to_expire.add(snapshot_id)<br>    return self<br>``` |

### `by_ids(snapshot_ids)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ExpireSnapshots.by_ids "Permanent link")

Expire multiple snapshots by their IDs.

This will mark the snapshots for expiration.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `snapshot_ids` | `List[int]` | List of snapshot IDs to expire. | _required_ |

Returns:
This for method chaining.

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>1106<br>1107<br>1108<br>1109<br>1110<br>1111<br>1112<br>1113<br>1114<br>1115<br>1116<br>1117<br>1118<br>1119<br>``` | ```<br>def by_ids(self, snapshot_ids: list[int]) -> ExpireSnapshots:<br>    """<br>    Expire multiple snapshots by their IDs.<br>    This will mark the snapshots for expiration.<br>    Args:<br>        snapshot_ids (List[int]): List of snapshot IDs to expire.<br>    Returns:<br>        This for method chaining.<br>    """<br>    for snapshot_id in snapshot_ids:<br>        self.by_id(snapshot_id)<br>    return self<br>``` |

### `older_than(dt)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ExpireSnapshots.older_than "Permanent link")

Expire all unprotected snapshots with a timestamp older than a given value.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `dt` | `datetime` | Only snapshots with datetime < this value will be expired. | _required_ |

Returns:

| Type | Description |
| --- | --- |
| `ExpireSnapshots` | This for method chaining. |

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>1121<br>1122<br>1123<br>1124<br>1125<br>1126<br>1127<br>1128<br>1129<br>1130<br>1131<br>1132<br>1133<br>1134<br>1135<br>1136<br>``` | ```<br>def older_than(self, dt: datetime) -> ExpireSnapshots:<br>    """<br>    Expire all unprotected snapshots with a timestamp older than a given value.<br>    Args:<br>        dt (datetime): Only snapshots with datetime < this value will be expired.<br>    Returns:<br>        This for method chaining.<br>    """<br>    protected_ids = self._get_protected_snapshot_ids()<br>    expire_from = datetime_to_millis(dt)<br>    for snapshot in self._transaction.table_metadata.snapshots:<br>        if snapshot.timestamp_ms < expire_from and snapshot.snapshot_id not in protected_ids:<br>            self._snapshot_ids_to_expire.add(snapshot.snapshot_id)<br>    return self<br>``` |

## `ManageSnapshots` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots "Permanent link")

Bases: `UpdateTableMetadata['ManageSnapshots']`

Run snapshot management operations using APIs.

APIs include create branch, create tag, etc.

Use table.manage\_snapshots().().commit() to run a specific operation.
Use table.manage\_snapshots().().().commit() to run multiple operations.
Pending changes are applied on commit.

We can also use context managers to make more changes. For example,

with table.manage\_snapshots() as ms:
ms.create\_tag(snapshot\_id1, "Tag\_A").create\_tag(snapshot\_id2, "Tag\_B")

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br> 810<br> 811<br> 812<br> 813<br> 814<br> 815<br> 816<br> 817<br> 818<br> 819<br> 820<br> 821<br> 822<br> 823<br> 824<br> 825<br> 826<br> 827<br> 828<br> 829<br> 830<br> 831<br> 832<br> 833<br> 834<br> 835<br> 836<br> 837<br> 838<br> 839<br> 840<br> 841<br> 842<br> 843<br> 844<br> 845<br> 846<br> 847<br> 848<br> 849<br> 850<br> 851<br> 852<br> 853<br> 854<br> 855<br> 856<br> 857<br> 858<br> 859<br> 860<br> 861<br> 862<br> 863<br> 864<br> 865<br> 866<br> 867<br> 868<br> 869<br> 870<br> 871<br> 872<br> 873<br> 874<br> 875<br> 876<br> 877<br> 878<br> 879<br> 880<br> 881<br> 882<br> 883<br> 884<br> 885<br> 886<br> 887<br> 888<br> 889<br> 890<br> 891<br> 892<br> 893<br> 894<br> 895<br> 896<br> 897<br> 898<br> 899<br> 900<br> 901<br> 902<br> 903<br> 904<br> 905<br> 906<br> 907<br> 908<br> 909<br> 910<br> 911<br> 912<br> 913<br> 914<br> 915<br> 916<br> 917<br> 918<br> 919<br> 920<br> 921<br> 922<br> 923<br> 924<br> 925<br> 926<br> 927<br> 928<br> 929<br> 930<br> 931<br> 932<br> 933<br> 934<br> 935<br> 936<br> 937<br> 938<br> 939<br> 940<br> 941<br> 942<br> 943<br> 944<br> 945<br> 946<br> 947<br> 948<br> 949<br> 950<br> 951<br> 952<br> 953<br> 954<br> 955<br> 956<br> 957<br> 958<br> 959<br> 960<br> 961<br> 962<br> 963<br> 964<br> 965<br> 966<br> 967<br> 968<br> 969<br> 970<br> 971<br> 972<br> 973<br> 974<br> 975<br> 976<br> 977<br> 978<br> 979<br> 980<br> 981<br> 982<br> 983<br> 984<br> 985<br> 986<br> 987<br> 988<br> 989<br> 990<br> 991<br> 992<br> 993<br> 994<br> 995<br> 996<br> 997<br> 998<br> 999<br>1000<br>1001<br>1002<br>1003<br>1004<br>1005<br>1006<br>1007<br>1008<br>1009<br>1010<br>1011<br>1012<br>1013<br>1014<br>1015<br>1016<br>1017<br>1018<br>1019<br>1020<br>1021<br>1022<br>1023<br>1024<br>1025<br>1026<br>1027<br>1028<br>1029<br>1030<br>1031<br>1032<br>``` | ```<br>class ManageSnapshots(UpdateTableMetadata["ManageSnapshots"]):<br>    """<br>    Run snapshot management operations using APIs.<br>    APIs include create branch, create tag, etc.<br>    Use table.manage_snapshots().<operation>().commit() to run a specific operation.<br>    Use table.manage_snapshots().<operation-one>().<operation-two>().commit() to run multiple operations.<br>    Pending changes are applied on commit.<br>    We can also use context managers to make more changes. For example,<br>    with table.manage_snapshots() as ms:<br>       ms.create_tag(snapshot_id1, "Tag_A").create_tag(snapshot_id2, "Tag_B")<br>    """<br>    _updates: tuple[TableUpdate, ...]<br>    _requirements: tuple[TableRequirement, ...]<br>    def __init__(self, transaction: Transaction) -> None:<br>        super().__init__(transaction)<br>        self._updates = ()<br>        self._requirements = ()<br>    def _commit(self) -> UpdatesAndRequirements:<br>        """Apply the pending changes and commit."""<br>        return self._updates, self._requirements<br>    def _commit_if_ref_updates_exist(self) -> None:<br>        """Stage any pending ref updates to the transaction state."""<br>        if self._updates:<br>            self._transaction._stage(*self._commit())<br>            self._updates = ()<br>            self._requirements = ()<br>    def _remove_ref_snapshot(self, ref_name: str) -> ManageSnapshots:<br>        """Remove a snapshot ref.<br>        Args:<br>            ref_name: branch / tag name to remove<br>        Stages the updates and requirements for the remove-snapshot-ref.<br>        Returns<br>            This method for chaining<br>        """<br>        updates = (RemoveSnapshotRefUpdate(ref_name=ref_name),)<br>        requirements = (<br>            AssertRefSnapshotId(<br>                snapshot_id=self._transaction.table_metadata.refs[ref_name].snapshot_id<br>                if ref_name in self._transaction.table_metadata.refs<br>                else None,<br>                ref=ref_name,<br>            ),<br>        )<br>        self._updates += updates<br>        self._requirements += requirements<br>        return self<br>    def create_tag(self, snapshot_id: int, tag_name: str, max_ref_age_ms: int | None = None) -> ManageSnapshots:<br>        """<br>        Create a new tag pointing to the given snapshot id.<br>        Args:<br>            snapshot_id (int): snapshot id of the existing snapshot to tag<br>            tag_name (str): name of the tag<br>            max_ref_age_ms (Optional[int]): max ref age in milliseconds<br>        Returns:<br>            This for method chaining<br>        """<br>        update, requirement = self._transaction._set_ref_snapshot(<br>            snapshot_id=snapshot_id,<br>            ref_name=tag_name,<br>            type=SnapshotRefType.TAG,<br>            max_ref_age_ms=max_ref_age_ms,<br>        )<br>        self._updates += update<br>        self._requirements += requirement<br>        return self<br>    def remove_tag(self, tag_name: str) -> ManageSnapshots:<br>        """<br>        Remove a tag.<br>        Args:<br>            tag_name (str): name of tag to remove<br>        Returns:<br>            This for method chaining<br>        """<br>        return self._remove_ref_snapshot(ref_name=tag_name)<br>    def create_branch(<br>        self,<br>        snapshot_id: int,<br>        branch_name: str,<br>        max_ref_age_ms: int | None = None,<br>        max_snapshot_age_ms: int | None = None,<br>        min_snapshots_to_keep: int | None = None,<br>    ) -> ManageSnapshots:<br>        """<br>        Create a new branch pointing to the given snapshot id.<br>        Args:<br>            snapshot_id (int): snapshot id of existing snapshot at which the branch is created.<br>            branch_name (str): name of the new branch<br>            max_ref_age_ms (Optional[int]): max ref age in milliseconds<br>            max_snapshot_age_ms (Optional[int]): max age of snapshots to keep in milliseconds<br>            min_snapshots_to_keep (Optional[int]): min number of snapshots to keep for the branch<br>        Returns:<br>            This for method chaining<br>        """<br>        update, requirement = self._transaction._set_ref_snapshot(<br>            snapshot_id=snapshot_id,<br>            ref_name=branch_name,<br>            type=SnapshotRefType.BRANCH,<br>            max_ref_age_ms=max_ref_age_ms,<br>            max_snapshot_age_ms=max_snapshot_age_ms,<br>            min_snapshots_to_keep=min_snapshots_to_keep,<br>        )<br>        self._updates += update<br>        self._requirements += requirement<br>        return self<br>    def remove_branch(self, branch_name: str) -> ManageSnapshots:<br>        """<br>        Remove a branch.<br>        Args:<br>            branch_name (str): name of branch to remove<br>        Returns:<br>            This for method chaining<br>        """<br>        return self._remove_ref_snapshot(ref_name=branch_name)<br>    def set_current_snapshot(self, snapshot_id: int | None = None, ref_name: str | None = None) -> ManageSnapshots:<br>        """Set the current snapshot to a specific snapshot ID or ref.<br>        Args:<br>            snapshot_id: The ID of the snapshot to set as current.<br>            ref_name: The snapshot reference (branch or tag) to set as current.<br>        Returns:<br>            This for method chaining.<br>        Raises:<br>            ValueError: If neither or both arguments are provided, or if the snapshot/ref does not exist.<br>        """<br>        self._commit_if_ref_updates_exist()<br>        if (snapshot_id is None) == (ref_name is None):<br>            raise ValueError("Either snapshot_id or ref_name must be provided, not both")<br>        target_snapshot_id: int<br>        if snapshot_id is not None:<br>            target_snapshot_id = snapshot_id<br>        else:<br>            if ref_name not in self._transaction.table_metadata.refs:<br>                raise ValueError(f"Cannot find matching snapshot ID for ref: {ref_name}")<br>            target_snapshot_id = self._transaction.table_metadata.refs[ref_name].snapshot_id<br>        if self._transaction.table_metadata.snapshot_by_id(target_snapshot_id) is None:<br>            raise ValueError(f"Cannot set current snapshot to unknown snapshot id: {target_snapshot_id}")<br>        update, requirement = self._transaction._set_ref_snapshot(<br>            snapshot_id=target_snapshot_id,<br>            ref_name=MAIN_BRANCH,<br>            type=SnapshotRefType.BRANCH,<br>        )<br>        self._transaction._stage(update, requirement)<br>        return self<br>    def rollback_to_snapshot(self, snapshot_id: int) -> ManageSnapshots:<br>        """Rollback the table to the given snapshot id.<br>        The snapshot needs to be an ancestor of the current table state.<br>        Args:<br>            snapshot_id (int): rollback to this snapshot_id that used to be current.<br>        Returns:<br>            This for method chaining<br>        Raises:<br>            ValueError: If the snapshot does not exist or is not an ancestor of the current table state.<br>        """<br>        if not self._transaction.table_metadata.snapshot_by_id(snapshot_id):<br>            raise ValueError(f"Cannot roll back to unknown snapshot id: {snapshot_id}")<br>        if not self._is_current_ancestor(snapshot_id):<br>            raise ValueError(f"Cannot roll back to snapshot, not an ancestor of the current state: {snapshot_id}")<br>        return self.set_current_snapshot(snapshot_id=snapshot_id)<br>    def rollback_to_timestamp(self, timestamp_ms: int) -> ManageSnapshots:<br>        """Rollback the table to the latest snapshot before the given timestamp.<br>        Finds the latest ancestor snapshot whose timestamp is before the given timestamp and rolls back to it.<br>        Args:<br>            timestamp_ms: Rollback to the latest snapshot before this timestamp in milliseconds.<br>        Returns:<br>            This for method chaining<br>        Raises:<br>            ValueError: If no valid snapshot exists older than the given timestamp.<br>        """<br>        snapshot = latest_ancestor_before_timestamp(self._transaction.table_metadata, timestamp_ms)<br>        if snapshot is None:<br>            raise ValueError(f"Cannot roll back, no valid snapshot older than: {timestamp_ms}")<br>        return self.set_current_snapshot(snapshot_id=snapshot.snapshot_id)<br>    def _is_current_ancestor(self, snapshot_id: int) -> bool:<br>        return snapshot_id in self._current_ancestors()<br>    def _current_ancestors(self) -> set[int]:<br>        return {<br>            a.snapshot_id<br>            for a in ancestors_of(<br>                self._transaction.table_metadata.current_snapshot(),<br>                self._transaction.table_metadata,<br>            )<br>        }<br>``` |

### `create_branch(snapshot_id, branch_name, max_ref_age_ms=None, max_snapshot_age_ms=None, min_snapshots_to_keep=None)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.create_branch "Permanent link")

Create a new branch pointing to the given snapshot id.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `snapshot_id` | `int` | snapshot id of existing snapshot at which the branch is created. | _required_ |
| `branch_name` | `str` | name of the new branch | _required_ |
| `max_ref_age_ms` | `Optional[int]` | max ref age in milliseconds | `None` |
| `max_snapshot_age_ms` | `Optional[int]` | max age of snapshots to keep in milliseconds | `None` |
| `min_snapshots_to_keep` | `Optional[int]` | min number of snapshots to keep for the branch | `None` |

Returns:
This for method chaining

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>900<br>901<br>902<br>903<br>904<br>905<br>906<br>907<br>908<br>909<br>910<br>911<br>912<br>913<br>914<br>915<br>916<br>917<br>918<br>919<br>920<br>921<br>922<br>923<br>924<br>925<br>926<br>927<br>928<br>929<br>930<br>``` | ```<br>def create_branch(<br>    self,<br>    snapshot_id: int,<br>    branch_name: str,<br>    max_ref_age_ms: int | None = None,<br>    max_snapshot_age_ms: int | None = None,<br>    min_snapshots_to_keep: int | None = None,<br>) -> ManageSnapshots:<br>    """<br>    Create a new branch pointing to the given snapshot id.<br>    Args:<br>        snapshot_id (int): snapshot id of existing snapshot at which the branch is created.<br>        branch_name (str): name of the new branch<br>        max_ref_age_ms (Optional[int]): max ref age in milliseconds<br>        max_snapshot_age_ms (Optional[int]): max age of snapshots to keep in milliseconds<br>        min_snapshots_to_keep (Optional[int]): min number of snapshots to keep for the branch<br>    Returns:<br>        This for method chaining<br>    """<br>    update, requirement = self._transaction._set_ref_snapshot(<br>        snapshot_id=snapshot_id,<br>        ref_name=branch_name,<br>        type=SnapshotRefType.BRANCH,<br>        max_ref_age_ms=max_ref_age_ms,<br>        max_snapshot_age_ms=max_snapshot_age_ms,<br>        min_snapshots_to_keep=min_snapshots_to_keep,<br>    )<br>    self._updates += update<br>    self._requirements += requirement<br>    return self<br>``` |

### `create_tag(snapshot_id, tag_name, max_ref_age_ms=None)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.create_tag "Permanent link")

Create a new tag pointing to the given snapshot id.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `snapshot_id` | `int` | snapshot id of the existing snapshot to tag | _required_ |
| `tag_name` | `str` | name of the tag | _required_ |
| `max_ref_age_ms` | `Optional[int]` | max ref age in milliseconds | `None` |

Returns:

| Type | Description |
| --- | --- |
| `ManageSnapshots` | This for method chaining |

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>867<br>868<br>869<br>870<br>871<br>872<br>873<br>874<br>875<br>876<br>877<br>878<br>879<br>880<br>881<br>882<br>883<br>884<br>885<br>886<br>887<br>``` | ```<br>def create_tag(self, snapshot_id: int, tag_name: str, max_ref_age_ms: int | None = None) -> ManageSnapshots:<br>    """<br>    Create a new tag pointing to the given snapshot id.<br>    Args:<br>        snapshot_id (int): snapshot id of the existing snapshot to tag<br>        tag_name (str): name of the tag<br>        max_ref_age_ms (Optional[int]): max ref age in milliseconds<br>    Returns:<br>        This for method chaining<br>    """<br>    update, requirement = self._transaction._set_ref_snapshot(<br>        snapshot_id=snapshot_id,<br>        ref_name=tag_name,<br>        type=SnapshotRefType.TAG,<br>        max_ref_age_ms=max_ref_age_ms,<br>    )<br>    self._updates += update<br>    self._requirements += requirement<br>    return self<br>``` |

### `remove_branch(branch_name)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.remove_branch "Permanent link")

Remove a branch.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `branch_name` | `str` | name of branch to remove | _required_ |

Returns:
This for method chaining

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>932<br>933<br>934<br>935<br>936<br>937<br>938<br>939<br>940<br>941<br>``` | ```<br>def remove_branch(self, branch_name: str) -> ManageSnapshots:<br>    """<br>    Remove a branch.<br>    Args:<br>        branch_name (str): name of branch to remove<br>    Returns:<br>        This for method chaining<br>    """<br>    return self._remove_ref_snapshot(ref_name=branch_name)<br>``` |

### `remove_tag(tag_name)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.remove_tag "Permanent link")

Remove a tag.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `tag_name` | `str` | name of tag to remove | _required_ |

Returns:
This for method chaining

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>889<br>890<br>891<br>892<br>893<br>894<br>895<br>896<br>897<br>898<br>``` | ```<br>def remove_tag(self, tag_name: str) -> ManageSnapshots:<br>    """<br>    Remove a tag.<br>    Args:<br>        tag_name (str): name of tag to remove<br>    Returns:<br>        This for method chaining<br>    """<br>    return self._remove_ref_snapshot(ref_name=tag_name)<br>``` |

### `rollback_to_snapshot(snapshot_id)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.rollback_to_snapshot "Permanent link")

Rollback the table to the given snapshot id.

The snapshot needs to be an ancestor of the current table state.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `snapshot_id` | `int` | rollback to this snapshot\_id that used to be current. | _required_ |

Returns:

| Type | Description |
| --- | --- |
| `ManageSnapshots` | This for method chaining |

Raises:

| Type | Description |
| --- | --- |
| `ValueError` | If the snapshot does not exist or is not an ancestor of the current table state. |

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br> 980<br> 981<br> 982<br> 983<br> 984<br> 985<br> 986<br> 987<br> 988<br> 989<br> 990<br> 991<br> 992<br> 993<br> 994<br> 995<br> 996<br> 997<br> 998<br> 999<br>1000<br>``` | ```<br>def rollback_to_snapshot(self, snapshot_id: int) -> ManageSnapshots:<br>    """Rollback the table to the given snapshot id.<br>    The snapshot needs to be an ancestor of the current table state.<br>    Args:<br>        snapshot_id (int): rollback to this snapshot_id that used to be current.<br>    Returns:<br>        This for method chaining<br>    Raises:<br>        ValueError: If the snapshot does not exist or is not an ancestor of the current table state.<br>    """<br>    if not self._transaction.table_metadata.snapshot_by_id(snapshot_id):<br>        raise ValueError(f"Cannot roll back to unknown snapshot id: {snapshot_id}")<br>    if not self._is_current_ancestor(snapshot_id):<br>        raise ValueError(f"Cannot roll back to snapshot, not an ancestor of the current state: {snapshot_id}")<br>    return self.set_current_snapshot(snapshot_id=snapshot_id)<br>``` |

### `rollback_to_timestamp(timestamp_ms)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.rollback_to_timestamp "Permanent link")

Rollback the table to the latest snapshot before the given timestamp.

Finds the latest ancestor snapshot whose timestamp is before the given timestamp and rolls back to it.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `timestamp_ms` | `int` | Rollback to the latest snapshot before this timestamp in milliseconds. | _required_ |

Returns:

| Type | Description |
| --- | --- |
| `ManageSnapshots` | This for method chaining |

Raises:

| Type | Description |
| --- | --- |
| `ValueError` | If no valid snapshot exists older than the given timestamp. |

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>1002<br>1003<br>1004<br>1005<br>1006<br>1007<br>1008<br>1009<br>1010<br>1011<br>1012<br>1013<br>1014<br>1015<br>1016<br>1017<br>1018<br>1019<br>1020<br>``` | ```<br>def rollback_to_timestamp(self, timestamp_ms: int) -> ManageSnapshots:<br>    """Rollback the table to the latest snapshot before the given timestamp.<br>    Finds the latest ancestor snapshot whose timestamp is before the given timestamp and rolls back to it.<br>    Args:<br>        timestamp_ms: Rollback to the latest snapshot before this timestamp in milliseconds.<br>    Returns:<br>        This for method chaining<br>    Raises:<br>        ValueError: If no valid snapshot exists older than the given timestamp.<br>    """<br>    snapshot = latest_ancestor_before_timestamp(self._transaction.table_metadata, timestamp_ms)<br>    if snapshot is None:<br>        raise ValueError(f"Cannot roll back, no valid snapshot older than: {timestamp_ms}")<br>    return self.set_current_snapshot(snapshot_id=snapshot.snapshot_id)<br>``` |

### `set_current_snapshot(snapshot_id=None, ref_name=None)` [¶](https://py.iceberg.apache.org/reference/pyiceberg/table/update/snapshot/\#pyiceberg.table.update.snapshot.ManageSnapshots.set_current_snapshot "Permanent link")

Set the current snapshot to a specific snapshot ID or ref.

Parameters:

| Name | Type | Description | Default |
| --- | --- | --- | --- |
| `snapshot_id` | `int | None` | The ID of the snapshot to set as current. | `None` |
| `ref_name` | `str | None` | The snapshot reference (branch or tag) to set as current. | `None` |

Returns:

| Type | Description |
| --- | --- |
| `ManageSnapshots` | This for method chaining. |

Raises:

| Type | Description |
| --- | --- |
| `ValueError` | If neither or both arguments are provided, or if the snapshot/ref does not exist. |

Source code in `pyiceberg/table/update/snapshot.py`

|     |     |
| --- | --- |
| ```<br>943<br>944<br>945<br>946<br>947<br>948<br>949<br>950<br>951<br>952<br>953<br>954<br>955<br>956<br>957<br>958<br>959<br>960<br>961<br>962<br>963<br>964<br>965<br>966<br>967<br>968<br>969<br>970<br>971<br>972<br>973<br>974<br>975<br>976<br>977<br>978<br>``` | ```<br>def set_current_snapshot(self, snapshot_id: int | None = None, ref_name: str | None = None) -> ManageSnapshots:<br>    """Set the current snapshot to a specific snapshot ID or ref.<br>    Args:<br>        snapshot_id: The ID of the snapshot to set as current.<br>        ref_name: The snapshot reference (branch or tag) to set as current.<br>    Returns:<br>        This for method chaining.<br>    Raises:<br>        ValueError: If neither or both arguments are provided, or if the snapshot/ref does not exist.<br>    """<br>    self._commit_if_ref_updates_exist()<br>    if (snapshot_id is None) == (ref_name is None):<br>        raise ValueError("Either snapshot_id or ref_name must be provided, not both")<br>    target_snapshot_id: int<br>    if snapshot_id is not None:<br>        target_snapshot_id = snapshot_id<br>    else:<br>        if ref_name not in self._transaction.table_metadata.refs:<br>            raise ValueError(f"Cannot find matching snapshot ID for ref: {ref_name}")<br>        target_snapshot_id = self._transaction.table_metadata.refs[ref_name].snapshot_id<br>    if self._transaction.table_metadata.snapshot_by_id(target_snapshot_id) is None:<br>        raise ValueError(f"Cannot set current snapshot to unknown snapshot id: {target_snapshot_id}")<br>    update, requirement = self._transaction._set_ref_snapshot(<br>        snapshot_id=target_snapshot_id,<br>        ref_name=MAIN_BRANCH,<br>        type=SnapshotRefType.BRANCH,<br>    )<br>    self._transaction._stage(update, requirement)<br>    return self<br>``` |

Back to top