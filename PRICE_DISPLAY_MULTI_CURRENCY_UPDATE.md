# Price Display Multi-Currency Update

Implemented the recommended scalable price-display model for Ventio.

## What changed

The old display modes were tied to two hard-coded currencies:

- USD only
- LBP only
- USD + LBP

These were replaced by a scalable model:

- `default`: show the default sale invoice currency only
- `selectable`: keep the UI ready for user-selected display currency
- `multiple`: show a configurable list of currencies

## New StoreProfile field

Added:

```dart
priceDisplayCurrencies: List<String>
```

This stores which active currencies should be displayed when `priceDisplayMode == 'multiple'`.

## Backward compatibility

Legacy values are normalized on load:

- `both` -> `multiple` with USD/LBP selected
- `usd` -> `default`
- `lbp` -> `default` with LBP display when available

## UI changes

Financial Settings now shows:

- Default currency only
- Allow currency switching
- Show multiple currencies

When “Show multiple currencies” is selected, the user can choose currencies with chips from the active currency list. At least one currency remains selected.

## Formatting changes

`formatUsdReferenceAmount` no longer assumes USD/LBP only. It now formats prices using `priceDisplayMode` and `priceDisplayCurrencies`, converting from the USD reference price to the selected display currencies.
