using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;

class BetterGarminView extends WatchUi.WatchFace {
    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
    }

    function onUpdate(dc) {
        var clockTime = System.getClockTime();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var timeString = Lang.format("$1$:$2$", [
            clockTime.hour,
            clockTime.min.format("%02d")
        ]);
        var secString = clockTime.sec.format("%02d");

        var mainFont = Graphics.FONT_NUMBER_THAI_HOT;
        var secFont = Graphics.FONT_TINY;

        var mainWidth = dc.getTextWidthInPixels(timeString, mainFont);
        var mainHeight = dc.getFontHeight(mainFont);
        var secWidth = dc.getTextWidthInPixels(secString, secFont);
        var secHeight = dc.getFontHeight(secFont);

        var totalWidth = mainWidth + secWidth;
        var startX = (dc.getWidth() - totalWidth) / 2;
        var centerY = dc.getHeight() / 2;
        var mainTop = centerY - mainHeight / 2;
        var secTop = mainTop + (mainHeight - secHeight) * 0.20;

        dc.drawText(
            startX,
            mainTop,
            mainFont,
            timeString,
            Graphics.TEXT_JUSTIFY_LEFT
        );

        dc.drawText(
            startX + mainWidth,
            secTop,
            secFont,
            secString,
            Graphics.TEXT_JUSTIFY_LEFT
        );
    }

    function onPartialUpdate(dc) {
    }

    function onEnterSleep() {
    }

    function onExitSleep() {
    }
}
