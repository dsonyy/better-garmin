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
        return false;
    }
}
