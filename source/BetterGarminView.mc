using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Weather;
using Toybox.ActivityMonitor;

class BetterGarminView extends WatchUi.WatchFace {
    // Bounding boxes for long-press detection [x, y, w, h]
    var mDateBox = null;
    var mWeatherBox = null;
    var mHrBox = null;
    var mStepsBox = null;
    var mFloorsBox = null;
    var mActiveMinBox = null;

    // Sleep state for low-power mode
    var mIsSleeping = false;

    // Bitmap icons (loaded in onLayout)
    var mIconHeart = null;
    var mIconSteps = null;
    var mIconFloors = null;
    var mIconActive = null;
    var mWeatherIcons = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
        mIconHeart = WatchUi.loadResource(Rez.Drawables.IconHeart);
        mIconSteps = WatchUi.loadResource(Rez.Drawables.IconSteps);
        mIconFloors = WatchUi.loadResource(Rez.Drawables.IconFloors);
        mIconActive = WatchUi.loadResource(Rez.Drawables.IconActive);
        mWeatherIcons = {
            0 => WatchUi.loadResource(Rez.Drawables.IconWeatherClear),       // Clear, mostly clear, fair
            1 => WatchUi.loadResource(Rez.Drawables.IconWeatherPartlyCloudy), // Partly cloudy/clear, thin clouds
            2 => WatchUi.loadResource(Rez.Drawables.IconWeatherCloudy),       // Mostly cloudy, cloudy, fog, hazy
            3 => WatchUi.loadResource(Rez.Drawables.IconWeatherRain),         // Rain, showers, drizzle
            4 => WatchUi.loadResource(Rez.Drawables.IconWeatherSnow),         // Snow, wintry mix, flurries
            6 => WatchUi.loadResource(Rez.Drawables.IconWeatherThunder)       // Thunderstorms
        };
    }

    function onUpdate(dc) {
        var clockTime = System.getClockTime();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var screenW = dc.getWidth();
        var screenH = dc.getHeight();
        var centerY = screenH / 2;

        var mainFont = Graphics.FONT_NUMBER_THAI_HOT;
        var secFont = Graphics.FONT_TINY;
        var dataFont = Graphics.FONT_SMALL;

        var mainHeight = dc.getFontHeight(mainFont);
        var dataHeight = dc.getFontHeight(dataFont);

        var timeString = Lang.format("$1$:$2$", [
            clockTime.hour,
            clockTime.min.format("%02d")
        ]);

        // Low-power mode: only HH:MM + date
        if (mIsSleeping) {
            dc.drawText(screenW / 2, centerY - mainHeight / 2, mainFont, timeString, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenW / 2, centerY - mainHeight / 2 - dataHeight - 8, dataFont, getDateString(), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Full mode: draw time with seconds
        var secString = clockTime.sec.format("%02d");
        var mainWidth = dc.getTextWidthInPixels(timeString, mainFont);
        var secWidth = dc.getTextWidthInPixels(secString, secFont);
        var secHeight = dc.getFontHeight(secFont);

        var totalWidth = mainWidth + secWidth;
        var startX = (screenW - totalWidth) / 2;
        var mainTop = centerY - mainHeight / 2;
        var secTop = mainTop + (mainHeight - secHeight) * 0.20;

        dc.drawText(startX, mainTop, mainFont, timeString, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(startX + mainWidth, secTop, secFont, secString, Graphics.TEXT_JUSTIFY_LEFT);

        // Row positions
        var row1Y = centerY - mainHeight / 2 - dataHeight * 2 - 16;  // Date
        var row2Y = centerY - mainHeight / 2 - dataHeight - 8;        // Weather
        var row3Y = centerY + mainHeight / 2 + 8;                      // HR + Steps
        var row4Y = centerY + mainHeight / 2 + dataHeight + 16;        // Floors + Active Min

        var leftX = screenW / 4;
        var rightX = screenW * 3 / 4;

        // Row 1: Date (centered)
        var dateStr = getDateString();
        dc.drawText(screenW / 2, row1Y, dataFont, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
        var dateW = dc.getTextWidthInPixels(dateStr, dataFont);
        mDateBox = [screenW / 2 - dateW / 2, row1Y, dateW, dataHeight];

        // Row 2: Weather icon + temp (centered)
        var weatherStr = getWeatherString();
        var weatherIcon = getWeatherIcon();
        drawIconField(dc, screenW / 2, row2Y, weatherIcon, weatherStr, dataFont, dataHeight);
        var weatherTotalW = getIconFieldWidth(dc, weatherIcon, weatherStr, dataFont);
        mWeatherBox = [screenW / 2 - weatherTotalW / 2, row2Y, weatherTotalW, dataHeight];

        // Row 3: HR (left) + Steps (right)
        var hrStr = getHeartRate();
        drawIconField(dc, leftX, row3Y, mIconHeart, hrStr, dataFont, dataHeight);
        var hrTotalW = getIconFieldWidth(dc, mIconHeart, hrStr, dataFont);
        mHrBox = [leftX - hrTotalW / 2, row3Y, hrTotalW, dataHeight];

        var activityData = getActivityData();

        var stepsStr = activityData[:steps];
        drawIconField(dc, rightX, row3Y, mIconSteps, stepsStr, dataFont, dataHeight);
        var stepsTotalW = getIconFieldWidth(dc, mIconSteps, stepsStr, dataFont);
        mStepsBox = [rightX - stepsTotalW / 2, row3Y, stepsTotalW, dataHeight];

        // Row 4: Floors (left) + Active Min (right)
        var floorsStr = activityData[:floors];
        drawIconField(dc, leftX, row4Y, mIconFloors, floorsStr, dataFont, dataHeight);
        var floorsTotalW = getIconFieldWidth(dc, mIconFloors, floorsStr, dataFont);
        mFloorsBox = [leftX - floorsTotalW / 2, row4Y, floorsTotalW, dataHeight];

        var activeStr = activityData[:activeMin];
        drawIconField(dc, rightX, row4Y, mIconActive, activeStr, dataFont, dataHeight);
        var activeTotalW = getIconFieldWidth(dc, mIconActive, activeStr, dataFont);
        mActiveMinBox = [rightX - activeTotalW / 2, row4Y, activeTotalW, dataHeight];
    }

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

    function drawIconField(dc, centerX, y, icon, text, font, fontHeight) {
        var iconSize = 24;
        var iconGap = 4;
        var textW = dc.getTextWidthInPixels(text, font);

        if (icon != null) {
            var totalW = iconSize + iconGap + textW;
            var fieldStartX = centerX - totalW / 2;
            dc.drawBitmap(fieldStartX, y + (fontHeight - iconSize) / 2, icon);
            dc.drawText(fieldStartX + iconSize + iconGap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(centerX, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function getIconFieldWidth(dc, icon, text, font) {
        var textW = dc.getTextWidthInPixels(text, font);
        if (icon != null) {
            return 24 + 4 + textW;
        }
        return textW;
    }

    function getWeatherIcon() {
        if (Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null && conditions.condition != null) {
                var code = conditions.condition;
                // Map condition codes to icon groups
                // Clear: 0, 23, 40
                if (code == 0 || code == 23 || code == 40) {
                    return mWeatherIcons[0];
                }
                // Partly cloudy: 1, 22, 52
                if (code == 1 || code == 22 || code == 52) {
                    return mWeatherIcons[1];
                }
                // Cloudy: 2, 5, 8, 9, 20, 29, 30, 33, 39
                if (code == 2 || code == 5 || code == 8 || code == 9 || code == 20 || code == 29 || code == 30 || code == 33 || code == 39) {
                    return mWeatherIcons[2];
                }
                // Rain: 3, 10, 11, 14, 15, 24, 25, 26, 27, 31, 49
                if (code == 3 || code == 10 || code == 11 || code == 14 || code == 15 || code == 24 || code == 25 || code == 26 || code == 27 || code == 31 || code == 49) {
                    return mWeatherIcons[3];
                }
                // Snow: 4, 7, 16, 17, 18, 19, 21, 34, 43, 44, 48, 50, 51
                if (code == 4 || code == 7 || code == 16 || code == 17 || code == 18 || code == 19 || code == 21 || code == 34 || code == 43 || code == 44 || code == 48 || code == 50 || code == 51) {
                    return mWeatherIcons[4];
                }
                // Thunder: 6, 12, 28
                if (code == 6 || code == 12 || code == 28) {
                    return mWeatherIcons[6];
                }
                // Default: cloudy
                return mWeatherIcons[2];
            }
        }
        return null;
    }

    function isInArea(x, y, box) {
        if (box == null) { return false; }
        return (x >= box[0] && x <= box[0] + box[2] && y >= box[1] && y <= box[1] + box[3]);
    }

    function onPartialUpdate(dc) {
    }

    function onEnterSleep() {
        mIsSleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        mIsSleeping = false;
        WatchUi.requestUpdate();
    }
}
