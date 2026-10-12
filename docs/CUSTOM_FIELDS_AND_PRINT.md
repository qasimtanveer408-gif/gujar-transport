# Custom fields and printing

Open Fields & print settings with settings.manage permission. Choose Drivers, Vehicles, Trips or Maintenance, then Add custom field. Specify a label, immutable cf_ key, data type, default, required status, order and visibility. Edit labels/settings later; archive fields to retain historical values. An archived field must first be removed from active dependent formulas.

Supported types are text, number, date, currency, percentage, dropdown, checkbox and formula. Dropdown choices use one line per option. Required numeric zero and checkbox false are accepted values. Dates use real calendar dates. No values are saved only in browser storage.

Formula keys are inserted using the numeric-field buttons. Use + - * / %, parentheses, SUM, MIN, MAX, ABS and ROUND. Decimal arithmetic is bounded; syntax is parsed into a validated tree. Formula values are read-only and calculated from authorized current saved fields. ROUND supports zero to six decimal places. Inputs or dependencies that are unavailable show an error; division by zero never becomes Infinity. Cycles and executable code are rejected. Permissions propagate through dependent formulas.

Example: create cf_quantity (Number), cf_rate (Currency), and cf_total (Formula) with cf_quantity * cf_rate. The editor updates the result as inputs change. Saving persists the inputs; reloading/printing calculates the result from them. Built-in financial formulas retain their existing business rules.

Card and register visibility are independent. Hidden/archived fields are omitted from record screens and printing while values remain stored. A financial restriction is enforced in the API/database as well as the UI.

Select a print document to change A4 portrait/landscape and up to six signature labels. Save the template. Signature spaces include blank physical lines, name and date. No digital or artificial signatures are inserted. Core record Print reloads the selected saved record, shows a preview, then opens browser Print / Save as PDF. Reference reports additionally export PDF and Excel directly.

Driver photos are optional. Upload a private JPEG/PNG in driver details, then select Use as profile photo. The image must belong to that driver and be ready in private Storage. Driver-update and driver-document permissions are required; deleting the source removes the profile selection.
