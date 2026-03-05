---
date: 2026-03-05T00:00:00+00:00
researcher: Claude
git_commit: a1875d6
branch: main
repository: better-garmin
topic: "Adding data fields, icons, and long-press interactions to the watch face"
tags: [research, codebase, watchface, activity-monitor, weather, complications, icons]
status: complete
last_updated: 2026-03-05
last_updated_by: Claude
---

# Research: Watch Face Data Fields, Icons, and Interactions

## Research Question

How to add date, weather, heart rate, steps, floors, active minutes (with icons) to the watch face in 4 rows (2 above, 2 below the HH:MM:SS display), and how to launch apps on long-press of each item.

## Summary

All 6 data fields are accessible via Toybox APIs with **no special permissions** needed. Long-press interactions use `WatchFaceDelegate.onPress()` + `Complications.exitTo()` (API 4.2.0+). Icons must be custom (no built-in icon fonts exist) — icon fonts are recommended over bitmaps for AMOLED.

---

## 1. Data APIs

### Date (Day of Week + Month + Day)
```monkeyc
using Toybox.Time;
using Toybox.Time.Gregorian;

var now = Time.now();
var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
var dateStr = info.day_of_week + ", " + info.month + " " + info.day;
// e.g. "Thu, Mar 5"
```

### Weather (Temperature in Celsius + Condition Code)
```monkeyc
using Toybox.Weather;

if (Toybox has :Weather) {
    var conditions = Weather.getCurrentConditions();
    if (conditions != null && conditions.temperature != null) {
        var temp = conditions.temperature;           // Already in Celsius
        var conditionCode = conditions.condition;    // Integer 0-53 for icon mapping
    }
}
```
Key condition codes: 0=Clear, 1=PartlyCloudy, 2=MostlyCloudy, 3=Rain, 4=Snow, 6=Thunderstorms, 20=Cloudy.

### Heart Rate
```monkeyc
using Toybox.ActivityMonitor;

var hrIterator = ActivityMonitor.getHeartRateHistory(1, true);
var sample = hrIterator.next();
if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
    var hr = sample.heartRate;
}
```

### Steps, Floors, Active Minutes
```monkeyc
var info = ActivityMonitor.getInfo();
var steps = info.steps;                              // Number
var floors = (info has :floorsClimbed) ? info.floorsClimbed : null;  // Number
var activeMin = (info.activeMinutesWeek != null) ? info.activeMinutesWeek.total : null;  // Number
```

**No permissions needed** for any of the above.

---

## 2. Long-Press Interactions

### Architecture
- Watch faces can **only** detect long press via `WatchFaceDelegate.onPress(clickEvent)` (no taps, swipes, or buttons)
- Launch apps with `Complications.exitTo(id)` — shows confirmation dialog
- Requires **API level 4.2.0+** (FR965 supports 5.0+)
- `manifest.xml` needs `minApiLevel="4.2.0"`

### Implementation Pattern

**BetterGarminApp.mc** — return delegate:
```monkeyc
function getInitialView() {
    var view = new BetterGarminView();
    var delegate = new BetterGarminDelegate(view);
    return [view, delegate];
}
```

**BetterGarminDelegate.mc** — handle press:
```monkeyc
class BetterGarminDelegate extends WatchUi.WatchFaceDelegate {
    private var mView;

    function initialize(view) {
        WatchFaceDelegate.initialize();
        mView = view;
    }

    function onPress(clickEvent) {
        var coords = clickEvent.getCoordinates();
        var x = coords[0];
        var y = coords[1];

        // Check bounding boxes stored by the view
        if (mView.isInArea(x, y, mView.mHrBox)) {
            Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_HEART_RATE));
            return true;
        }
        // ... similar for steps, weather, etc.
        return false;
    }
}
```

### Available Complication Types
| Complication | Constant |
|---|---|
| Heart Rate | `COMPLICATION_TYPE_HEART_RATE` |
| Steps | `COMPLICATION_TYPE_STEPS` |
| Floors | `COMPLICATION_TYPE_FLOORS_CLIMBED` |
| Weather | `COMPLICATION_TYPE_WEATHER` |
| Temperature | `COMPLICATION_TYPE_CURRENT_TEMPERATURE` |
| Calendar | `COMPLICATION_TYPE_CALENDAR_EVENTS` |

---

## 3. Icons

**No built-in icon fonts exist.** Two approaches:

### Option A: Icon Font (Recommended for AMOLED)
- Supports anti-aliasing, dynamic color changes, low memory
- Create with FontForge → BMFont/fontbm → `.fnt` + `.png`
- Map icons to characters (e.g., H=heart, S=steps)
- Declare in `resources/fonts/fonts.xml`
- Draw with `dc.drawText(x, y, iconFont, "H", ...)`

### Option B: Bitmap PNGs
- Simpler to create, no toolchain needed
- No alpha channel (use black background for AMOLED)
- Declare in `resources/drawables/drawables.xml`
- Load in `onLayout()`: `WatchUi.loadResource(Rez.Drawables.HeartIcon)`
- Draw with `dc.drawBitmap(x, y, bitmap)`

---

## 4. Proposed Layout (454×454 Round Screen)

```
┌──────────────────────────┐
│                          │
│     Thu, Mar 5           │  Row 1: Date
│     ☁ 12°C               │  Row 2: Weather + Temp
│                          │
│       14:3542            │  Center: HH:MM + SS
│                          │
│     ♥ 72    👟 8421       │  Row 3: HR + Steps
│     🏢 12   ⚽ 150        │  Row 4: Floors + Active Min
│                          │
└──────────────────────────┘
```

Each row should use `Graphics.FONT_SMALL` or `FONT_TINY` for data values. Icons should be ~20-24px if using bitmaps.

---

## 5. Manifest Changes Required

```xml
<iq:application ... minApiLevel="4.2.0" ...>
    <iq:permissions>
        <iq:uses-permission id="Complications" />
    </iq:permissions>
</iq:application>
```

---

## Code References
- `source/BetterGarminView.mc` — Current view with HH:MM:SS rendering
- `source/BetterGarminApp.mc` — App entry point, needs delegate addition
- `manifest.xml` — Needs API level bump and Complications permission
- `resources/drawables/drawables.xml` — Add icon bitmap definitions

## Open Questions
1. Icon design: Create custom PNGs or use an icon font? (Icon font recommended)
2. Color scheme: Should each data field have its own color (e.g., red heart, green steps)?
3. Low-power mode: Should data fields be hidden in always-on display to save power?
4. Weather icon mapping: Need to map 54 condition codes to a manageable set of icons (e.g., 6-8 icons)
