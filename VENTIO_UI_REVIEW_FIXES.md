# Ventio UI Review Fixes

This build focuses on usability fixes reported during Windows, Android, and Web testing.

## Fixed
- Replaced the Windows Flutter default icon with the Ventio icon.
- Updated Windows executable metadata to use Ventio branding.
- Replaced the wide Windows/Linux/Web side NavigationRail with a scrollable Ventio side menu so lower items are reachable on shorter screens.
- App bar now shows Ventio instead of the default "My Store" title when no real store name was configured.
- Default store profile name changed from "My Store" to "Ventio".
- Added a persistent mobile checkout bar in POS so Save / Complete Sale is visible even when the cart content is long.
- Made POS product cards taller and more tolerant of long product names/prices to avoid overlapping text on Android.
- Made product list rows responsive on narrow Android screens to reduce trailing text/button overlap.

## Still recommended for next QA pass
- Test on a small Android device around 360dp width.
- Test Arabic language layout in POS, products, settings, and reports.
- Test Windows at 1366x768 and with 125%-150% display scaling.
- Confirm whether the POS should default to Cart tab after adding a product.
