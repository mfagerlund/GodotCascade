# Collections, item models, and virtualization

`Repeat` accepts either an ordinary `Array` or a `CascadeItemModel`. Both paths build native Godot controls, preserve stable keyed identity, and update only the affected Repeat subtree. Collection-only refreshes do not construct a complete off-tree document candidate.

## Arrays and localized refresh

Existing Array bindings remain valid:

```xml
<Repeat items="{inventory.items}" key="id">
    <Row>
        <Label text="{item.name}" />
        <Label text="{item.quantity}" />
    </Row>
</Repeat>
```

After mutating the Array, call `refresh_binding_paths(PackedStringArray(["inventory.items"]))`, `refresh_bindings()`, or invalidate the collection path through `ObservableBindingContext`. GodotCascade builds a candidate for each outer affected Repeat—not for the whole document—and keyed reconciliation preserves compatible rows, writable scopes, focus, native state, and application signal connections. An Array invalidation rescans its keys because arbitrary in-place mutations have no typed delta; subsequent virtual scroll-window shifts reuse that validated list instead of rescanning the entire Array.

Missing or duplicate keys abort the collection patch atomically. The last valid native rows remain interactive and the document publishes a diagnostic. While a collection transaction is invalid, scroll-window changes cannot commit a partial view from stale keys. The next collection mutation retries every outer Repeat as one localized transaction; success clears the block, while another failure retains the last valid tree and diagnostics.

## Typed item models

`CascadeItemModel` is the event-driven collection interface:

```gdscript
func item_count() -> int
func item_at(index: int) -> Variant
func key_at(index: int) -> Variant
signal changed(change: CascadeCollectionChange)
```

`CascadeArrayItemModel` is the included mutable implementation:

```gdscript
var pilots := CascadeArrayItemModel.new(
    initial_pilots,
    func(pilot): return pilot.id
)

pilots.insert(0, new_pilot)
pilots.move_items(5, 1)
pilots.update(1, updated_pilot)
pilots.remove_at(3)
```

The model emits typed `INSERT`, `REMOVE`, `MOVE`, `UPDATE`, and `RESET` changes synchronously. A bound document listens automatically; no polling or explicit binding refresh is required. Invalid mutation arguments return `false` and emit nothing. Custom models can derive from `CascadeItemModel` for database, network, or domain-owned storage.

Virtual item-model repeats retain a validated full key index. `INSERT` and `UPDATE` read only the changed item range, `REMOVE` and `MOVE` transform the retained keys without rereading model items, and `RESET` performs a deliberate complete scan. A delta that introduces a missing or duplicate key updates the internal model-key state but leaves the last valid native tree untouched; a subsequent repairing delta can therefore recover without forcing a reset. `collection_stats().keys_scanned` reports the actual item keys read for the completed patch.

The GXML `key` remains authoritative when present. For a non-virtual item-model Repeat without `key`, `key_at()` supplies identity. Virtual Repeat deliberately requires an explicit `key` so the source contract remains reviewable.

## Fixed-height virtualization

Place a virtual Repeat below a `Scroll` ancestor:

```xml
<Scroll>
    <Repeat
        items="{inventory.items}"
        key="id"
        virtual="true"
        item-height="44"
        overscan="4">
        <Row>
            <Label text="{item.name}" />
            <Label text="{item.quantity}" />
        </Row>
    </Repeat>
</Scroll>
```

Only the visible fixed-height range, the requested rows above and below it, and at most one focused pinned row are native controls. Synthetic native spacer controls preserve the complete content height, so the ordinary Godot scrollbar still represents every model item. A window shift reconciles overlapping keys and reports `virtual_window` in the binding trace.

The initial contract is intentionally narrow and is validated both on full load and after bound values/classes are applied to a localized candidate:

- vertical, non-wrapping layout only;
- one stable key per item;
- positive fixed `item-height` in native pixels;
- non-negative integer `overscan` (default `3`);
- one `Scroll` ancestor;
- no nested virtual Repeat;
- no `if` on the virtual item root—filter the model before binding it;
- no conditional or bound `visible` on the virtual item root—filter the model before binding it; literal `visible="true"` is harmless and descendants may still bind visibility;
- no authored `autofocus` or `focus-trap` anywhere inside a Repeat template;
- no vertical margin on the repeated item root—put spacing in `item-height` or the Repeat `gap`;
- no vertical padding or border on the Repeat itself—put those on `Scroll`;
- every realized item's fresh native minimum height, including bound text and classes, must fit `item-height`; an overflowing update is rejected atomically;
- virtual tables require explicit non-content `grid-template-columns` and `row-gap: 0` so unseen cells cannot change column or row measurement.

Rows that leave the window are freed. Model-backed values return when a row is realized again, but transient unbound state such as an animation or an unfocused text caret is not cached. A focused row is pinned by stable key until focus moves outside the row. Collection changes preserve the first visible keyed item and its fractional intra-row pixel offset when that key still exists. The window uses the native vertical scrollbar's `page` as its effective viewport, so Scroll padding and borders do not overstate the visible range.

Variable-height virtualization, horizontal/wrapped windows, sticky table headers, and persistence of arbitrary ephemeral row state are not supported.

## Traces and debugger data

`CascadeDocument.collection_updated(repeats, stats)` fires after a successful localized patch. `collection_stats()` returns the latest bounded record, including candidate-control counts, scanned keys, model/realized counts, virtual ranges, focus pins, and `full_document_candidates`. The decisive collection invariant is:

```gdscript
assert(document.collection_stats().full_document_candidates == 0)
```

The editor debugger shows each Repeat's model type, total count, realized count, range, and overscan. `last_binding_trace().strategy` distinguishes `collection_patch` from `virtual_window` and ordinary targeted property refreshes.
