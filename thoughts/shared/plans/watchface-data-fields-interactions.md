# Watch Face Data Fields & Interactions — Implementation Plan

## Overview

Add 6 data fields (date, weather, heart rate, steps, floors, active minutes) with bitmap PNG icons to the watch face, arranged in 2 rows above and 2 rows below the HH:MM:SS display. Add long-press interaction to launch related apps via Complications API. Implement low-power mode showing only time + date.

## Current State Analysis

- **BetterGarminView.mc**: Renders `HH:MM` (FONT_NUMBER_THAI_HOT) + `SS` (FONT_TINY) centered on black background
- **BetterGarminApp.mc**: Returns `[new BetterGarminView()]` — no delegate
- **manifest.xml**: API level 3.4.0, no permissions, FR965 only
- **Resources**: Only launcher icon bitmap

### Key Discoveries:
- `onPartialUpdate`, `onEnterSleep`, `onExitSleep` are empty stubs (`BetterGarminView.mc:59-66`)
- No delegate is returned from `getInitialView()` (`BetterGarminApp.mc:15-17`)
- All data APIs (ActivityMonitor, Weather, Time.Gregorian) need no special permissions
- Complications API needs permission and API level 4.2.0+

## Desired End State

A watch face displaying:
```
┌──────────────────────────┐
│                          │
│     Thu, Mar 5           │  Row 1: Date (centered)
│     ☁ 12°C               │  Row 2: Weather icon + Temp
│                          │
│       14:35₄₂            │  Center: HH:MM + SS
│                          │
│     ♥ 72    👟 8421       │  Row 3: HR + Steps
│     ⬆ 12   ⚡ 150        │  Row 4: Floors + Active Min
│                          │
└──────────────────────────┘
```

- All text and icons in white on black
- Long-press on any data field launches the related app
- Low-power mode: only HH:MM + date visible (no seconds, no metrics, no weather)
- Bitmap PNG icons (~20-24px) for weather conditions, heart, steps, floors, active minutes

### Verification:
- Build succeeds: `make build` or SDK compile for fr965
- Deploy to FR965 simulator — all 6 fields display with correct values
- Long-press on each field opens confirmation dialog for the correct app
- Enter low-power mode — only time + date visible
- Wake from low-power — all fields reappear

## What We're NOT Doing

- Icon fonts (using bitmap PNGs instead)
- Colored icons/text (all white)
- Full weather condition icon mapping (start with 6-8 key icons, not all 54 codes)
- 12h/24h toggle (system handles this automatically)
- Partial update optimization for always-on seconds
- Multiple device support (FR965 only)

## Implementation Approach

Split into 4 phases, each building on the previous:
1. Data fields display (no icons)
2. Bitmap icons
3. Long-press interactions
4. Low-power mode

This lets us verify rendering before adding icons, and verify tap zones before optimizing power.

---

## Phase 1: Data Fields Display

### Overview
Add all 6 data fields to `BetterGarminView.mc` with text-only rendering. Restructure `onUpdate()` to lay out 4 rows around the centered time.

### Changes Required:

#### 1. BetterGarminView.mc — Add imports and data fetching
**File**: `source/BetterGarminView.mc`

Add imports at top:
```monkeyc
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Weather;
using Toybox.ActivityMonitor;
```

Add instance variables for bounding boxes (needed later for long-press):
```monkeyc
// Bounding boxes for long-press detection [x, y, w, h]
var mDateBox = null;
var mWeatherBox = null;
var mHrBox = null;
var mStepsBox = null;
var mFloorsBox = null;
var mActiveMinBox = null;
```

#### 2. BetterGarminView.mc — Restructure onUpdate()

Replace the current `onUpdate()` with a layout that:

1. Clears screen (black)
2. Gets clock time, date, weather, activity data
3. Computes vertical zones:
   - **Top zone** (above center): Row 1 (date) + Row 2 (weather)
   - **Center**: HH:MM + SS (existing logic)
   - **Bottom zone** (below center): Row 3 (HR + Steps) + Row 4 (Floors + Active Min)
4. Draws each row, storing bounding boxes

**Layout constants** (approximate for 454×454):
```monkeyc
// Vertical layout
var screenW = dc.getWidth();   // 454
var screenH = dc.getHeight();  // 454
var centerY = screenH / 2;

// Font choices
var dataFont = Graphics.FONT_SMALL;
var dataHeight = dc.getFontHeight(dataFont);

// Row Y positions (relative to center)
var row1Y = centerY - mainHeight/2 - dataHeight * 2 - 16;  // Date
var row2Y = centerY - mainHeight/2 - dataHeight - 8;        // Weather
var row3Y = centerY + mainHeight/2 + 8;                      // HR + Steps
var row4Y = centerY + mainHeight/2 + dataHeight + 16;        // Floors + Active Min
```

**Data fetching helper methods** to add:
```monkeyc
function getDateString() {
    var now = Time.now();
    var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
    return info.day_of_week + ", " + info.month + " " + info.day;
}

function getWeatherString() {
    if (Toybox has :Weather) {
        var conditions = Weather.getCurrentConditions();
        if (conditions != null && conditions.temperature != null) {
            return conditions.temperature.toString() + "°C";
        }
    }
    return "--°C";
}

function getHeartRate() {
    var hrIterator = ActivityMonitor.getHeartRateHistory(1, true);
    var sample = hrIterator.next();
    if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
        return sample.heartRate.toString();
    }
    return "--";
}

function getActivityData() {
    var info = ActivityMonitor.getInfo();
    return {
        :steps => info.steps != null ? info.steps.toString() : "--",
        :floors => (info has :floorsClimbed && info.floorsClimbed != null) ? info.floorsClimbed.toString() : "--",
        :activeMin => (info.activeMinutesWeek != null && info.activeMinutesWeek.total != null) ? info.activeMinutesWeek.total.toString() : "--"
    };
}
```

**Drawing rows 3 and 4** (two fields side by side):
```monkeyc
// Row 3: HR (left) + Steps (right)
var leftX = screenW / 4;       // ~113
var rightX = screenW * 3 / 4;  // ~341

// Draw HR centered at leftX
dc.drawText(leftX, row3Y, dataFont, hrString, Graphics.TEXT_JUSTIFY_CENTER);
// Draw Steps centered at rightX
dc.drawText(rightX, row3Y, dataFont, stepsString, Graphics.TEXT_JUSTIFY_CENTER);
```

**Store bounding boxes** after drawing each field:
```monkeyc
// Example for HR
var hrTextW = dc.getTextWidthInPixels(hrString, dataFont);
mHrBox = [leftX - hrTextW/2, row3Y, hrTextW, dataHeight];
```

#### 3. Add isInArea() helper
```monkeyc
function isInArea(x, y, box) {
    if (box == null) { return false; }
    return (x >= box[0] && x <= box[0] + box[2] && y >= box[1] && y <= box[1] + box[3]);
}
```

### Success Criteria:

#### Automated Verification:
- [x] Project compiles without errors for fr965
- [ ] No Monkey C linting warnings

#### Manual Verification:
- [ ] All 6 data fields display on simulator with correct values
- [ ] Date format is "Day, Mon DD" (e.g., "Thu, Mar 5")
- [ ] Weather shows temperature or "--°C" if unavailable
- [ ] HR, steps, floors, active minutes show values or "--"
- [ ] Time (HH:MM:SS) still centered and rendered correctly
- [ ] Layout looks balanced on 454×454 round screen

---

## Phase 2: Bitmap Icons

### Overview
Create ~20px white PNG icons for each data field and weather conditions. Load them in `onLayout()` and draw them before the text values.

### Changes Required:

#### 1. Create icon PNGs
**Directory**: `resources/drawables/`

Create white-on-transparent 24×24 PNG icons:
- `icon_heart.png` — heart symbol (HR)
- `icon_steps.png` — shoe/footprint (steps)
- `icon_floors.png` — stairs/arrow-up (floors)
- `icon_active.png` — lightning bolt (active minutes)
- `icon_weather_clear.png` — sun
- `icon_weather_cloudy.png` — cloud
- `icon_weather_rain.png` — cloud with rain
- `icon_weather_snow.png` — snowflake
- `icon_weather_thunder.png` — lightning
- `icon_weather_partly_cloudy.png` — sun behind cloud

#### 2. Register icons in drawables.xml
**File**: `resources/drawables/drawables.xml`
```xml
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
    <bitmap id="IconHeart" filename="icon_heart.png"/>
    <bitmap id="IconSteps" filename="icon_steps.png"/>
    <bitmap id="IconFloors" filename="icon_floors.png"/>
    <bitmap id="IconActive" filename="icon_active.png"/>
    <bitmap id="IconWeatherClear" filename="icon_weather_clear.png"/>
    <bitmap id="IconWeatherCloudy" filename="icon_weather_cloudy.png"/>
    <bitmap id="IconWeatherRain" filename="icon_weather_rain.png"/>
    <bitmap id="IconWeatherSnow" filename="icon_weather_snow.png"/>
    <bitmap id="IconWeatherThunder" filename="icon_weather_thunder.png"/>
    <bitmap id="IconWeatherPartlyCloudy" filename="icon_weather_partly_cloudy.png"/>
</drawables>
```

#### 3. Load icons in onLayout()
**File**: `source/BetterGarminView.mc`

Add instance variables and load in `onLayout()`:
```monkeyc
var mIconHeart = null;
var mIconSteps = null;
var mIconFloors = null;
var mIconActive = null;
var mWeatherIcons = null;  // Dictionary keyed by condition code

function onLayout(dc) {
    mIconHeart = WatchUi.loadResource(Rez.Drawables.IconHeart);
    mIconSteps = WatchUi.loadResource(Rez.Drawables.IconSteps);
    mIconFloors = WatchUi.loadResource(Rez.Drawables.IconFloors);
    mIconActive = WatchUi.loadResource(Rez.Drawables.IconActive);
    mWeatherIcons = {
        0 => WatchUi.loadResource(Rez.Drawables.IconWeatherClear),
        1 => WatchUi.loadResource(Rez.Drawables.IconWeatherPartlyCloudy),
        2 => WatchUi.loadResource(Rez.Drawables.IconWeatherCloudy),
        20 => WatchUi.loadResource(Rez.Drawables.IconWeatherCloudy),
        3 => WatchUi.loadResource(Rez.Drawables.IconWeatherRain),
        4 => WatchUi.loadResource(Rez.Drawables.IconWeatherSnow),
        6 => WatchUi.loadResource(Rez.Drawables.IconWeatherThunder)
    };
}
```

#### 4. Draw icons before text in onUpdate()

For each data field, draw the icon to the left of the text:
```monkeyc
// Example: Heart rate
var iconSize = 24;
var iconGap = 4;
var hrText = getHeartRate();
var hrTextW = dc.getTextWidthInPixels(hrText, dataFont);
var totalW = iconSize + iconGap + hrTextW;
var hrStartX = leftX - totalW / 2;

dc.drawBitmap(hrStartX, row3Y + (dataHeight - iconSize) / 2, mIconHeart);
dc.drawText(hrStartX + iconSize + iconGap, row3Y, dataFont, hrText, Graphics.TEXT_JUSTIFY_LEFT);

// Update bounding box to include icon
mHrBox = [hrStartX, row3Y, totalW, dataHeight];
```

For weather, select icon based on condition code:
```monkeyc
function getWeatherIcon(conditionCode) {
    if (mWeatherIcons != null && mWeatherIcons.hasKey(conditionCode)) {
        return mWeatherIcons[conditionCode];
    }
    // Default to cloudy for unmapped codes
    if (mWeatherIcons != null && mWeatherIcons.hasKey(20)) {
        return mWeatherIcons[20];
    }
    return null;
}
```

### Success Criteria:

#### Automated Verification:
- [x] All icon PNGs exist in `resources/drawables/`
- [x] Project compiles without errors
- [ ] No resource loading errors in simulator

#### Manual Verification:
- [ ] Each data field shows icon + value
- [ ] Icons are vertically centered with text
- [ ] Weather icon changes based on condition
- [ ] Icons are crisp at 24×24 on AMOLED display
- [ ] Layout still balanced with icons included

---

## Phase 3: Long-Press Interactions

### Overview
Add `BetterGarminDelegate` to handle long-press events. Use bounding boxes from the view to determine which field was pressed, and launch the corresponding app via Complications API.

### Changes Required:

#### 1. Update manifest.xml
**File**: `manifest.xml`

- Change `minApiLevel` from `"3.4.0"` to `"4.2.0"`
- Add Complications permission:
```xml
<iq:permissions>
    <iq:uses-permission id="Complications" />
</iq:permissions>
```

#### 2. Create BetterGarminDelegate.mc
**File**: `source/BetterGarminDelegate.mc` (new file)

```monkeyc
using Toybox.WatchUi;
using Toybox.Complications;

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

        if (mView.isInArea(x, y, mView.mHrBox)) {
            Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_HEART_RATE));
            return true;
        }
        if (mView.isInArea(x, y, mView.mStepsBox)) {
            Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_STEPS));
            return true;
        }
        if (mView.isInArea(x, y, mView.mFloorsBox)) {
            Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_FLOORS_CLIMBED));
            return true;
        }
        if (mView.isInArea(x, y, mView.mWeatherBox)) {
            Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE));
            return true;
        }
        if (mView.isInArea(x, y, mView.mDateBox)) {
            Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_CALENDAR_EVENTS));
            return true;
        }
        if (mView.isInArea(x, y, mView.mActiveMinBox)) {
            // No perfect match — use steps as fallback or skip
            return false;
        }
        return false;
    }
}
```

#### 3. Update BetterGarminApp.mc
**File**: `source/BetterGarminApp.mc`

Change `getInitialView()` to return the delegate:
```monkeyc
function getInitialView() {
    var view = new BetterGarminView();
    var delegate = new BetterGarminDelegate(view);
    return [view, delegate];
}
```

### Success Criteria:

#### Automated Verification:
- [x] Project compiles with updated manifest (API 4.2.0, Complications permission)
- [x] No type errors in delegate class

#### Manual Verification:
- [ ] Long-press on HR area → heart rate app confirmation dialog
- [ ] Long-press on steps area → steps app confirmation
- [ ] Long-press on floors area → floors app confirmation
- [ ] Long-press on weather area → weather/temperature app confirmation
- [ ] Long-press on date area → calendar events confirmation
- [ ] Long-press on empty area → nothing happens
- [ ] Bounding boxes accurately match visual positions

---

## Phase 4: Low-Power Mode

### Overview
Implement `onEnterSleep()` and `onExitSleep()` to toggle a flag. In `onUpdate()`, when in low-power mode, render only HH:MM + date (no seconds, no metrics, no weather, no icons).

### Changes Required:

#### 1. BetterGarminView.mc — Add sleep state
```monkeyc
var mIsSleeping = false;

function onEnterSleep() {
    mIsSleeping = true;
    WatchUi.requestUpdate();
}

function onExitSleep() {
    mIsSleeping = false;
    WatchUi.requestUpdate();
}
```

#### 2. BetterGarminView.mc — Conditional rendering in onUpdate()

At the top of `onUpdate()`, after drawing the time:
```monkeyc
if (mIsSleeping) {
    // Low-power mode: only draw HH:MM (no seconds) + date
    // Draw time centered (without seconds)
    dc.drawText(screenW / 2, centerY - mainHeight / 2, mainFont, timeString, Graphics.TEXT_JUSTIFY_CENTER);
    // Draw date below or above
    dc.drawText(screenW / 2, centerY - mainHeight / 2 - dataHeight - 8, dataFont, getDateString(), Graphics.TEXT_JUSTIFY_CENTER);
    return;
}
// ... full rendering continues
```

### Success Criteria:

#### Automated Verification:
- [x] Project compiles without errors

#### Manual Verification:
- [ ] When watch enters sleep mode, only HH:MM + date are visible
- [ ] Seconds are NOT shown in low-power mode
- [ ] Metrics, weather, and icons are NOT shown in low-power mode
- [ ] When waking up, all fields reappear immediately
- [ ] Low-power layout is centered and readable

---

## Testing Strategy

### Unit Tests:
- Test `getDateString()` format
- Test `getWeatherString()` with null conditions
- Test `getHeartRate()` with invalid sample
- Test `isInArea()` with boundary cases

### Manual Testing Steps:
1. Deploy to FR965 simulator
2. Verify all 6 data fields display with mock data
3. Verify weather icon selection for different condition codes
4. Long-press each data field — verify correct app launches
5. Toggle low-power mode — verify only time + date shown
6. Test with missing data (no weather, no HR) — verify "--" fallback
7. Test at different times (single-digit hour, midnight, noon)

## Performance Considerations

- `onUpdate()` is called every second in active mode — keep data fetching lightweight
- Bitmap icons are loaded once in `onLayout()`, not per frame
- Weather and activity data don't change every second — could cache, but the APIs are cheap enough for now
- In low-power mode, system calls `onUpdate()` once per minute, so the early return saves significant work

## References

- Research: `thoughts/shared/research/2026-03-05_watchface-data-fields-interactions.md`
- Current view: `source/BetterGarminView.mc`
- Current app: `source/BetterGarminApp.mc`
- Manifest: `manifest.xml`
