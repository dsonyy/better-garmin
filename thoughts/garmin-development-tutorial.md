# Creating custom Garmin watch faces for Forerunner 965

**The complete development and publishing workflow for Garmin watch faces is free, well-documented, and achievable in a few days.** You'll use Monkey C (Garmin's purpose-built language), the Connect IQ SDK, and Visual Studio Code to develop watch faces that can be published to the Connect IQ Store at no cost. The Forerunner 965's **454×454 AMOLED display** and **~512 KB memory limit** make it one of the most capable devices for watch face development, supporting full 24-bit color, GPU-accelerated anti-aliasing, and partial updates for always-on display modes.

This guide covers everything from setting up your developer account to publishing and open-sourcing your watch face.

---

## Setting up your development environment takes about 30 minutes

Creating a Garmin developer account is free and instant. Navigate to **developer.garmin.com/connect-iq/sdk/** and create an account when prompted to download the SDK. You must be at least 18 years old and agree to the Connect IQ Developer Agreement. There's no waiting period—you can start developing immediately after registration.

The Connect IQ SDK (currently version **8.4.0**, released December 2025) is available for Windows, macOS, and Linux. Download the SDK Manager for your platform, launch it, sign in with your Garmin account, and use it to download both the latest SDK version and the Forerunner 965 device simulator. The SDK includes the Monkey C compiler (`monkeyc`), device simulators (`connectiq`), the app runner (`monkeydo`), sample projects, and complete API documentation. A Java Runtime Environment (version 8+) is required.

Visual Studio Code with the official **Monkey C extension from Garmin** is the recommended IDE. Install VS Code, search for "Monkey C" in the Extensions marketplace (the extension has over 144,000 installations), and verify your setup using the command palette: `Monkey C: Verify Installation`. The extension provides autocomplete, syntax highlighting, real-time error detection, integrated building and debugging, and a project creation wizard. While Eclipse is still supported, Garmin now recommends VS Code for all new development.

**Every app must be signed with a developer key.** Generate one using the VS Code command `Monkey C: Generate a Developer Key`, which creates an RSA 4096-bit key saved as a `.der` file. Keep this key safe—losing it means you cannot update published apps.

---

## Watch face project structure and Monkey C fundamentals

A watch face project follows a standard structure with the manifest, build configuration, source files, and resources organized into specific directories:

```
MyWatchFace/
├── manifest.xml              # App configuration (type, permissions, devices)
├── monkey.jungle             # Build configuration
├── source/
│   ├── MyWatchFaceApp.mc     # Application entry point
│   └── MyWatchFaceView.mc    # Watch face view and drawing logic
├── resources/
│   ├── layouts/              # UI layout definitions
│   ├── drawables/            # Images and launcher icon
│   └── strings/              # Localization strings
└── resources-fr965/          # Optional device-specific resources
```

Monkey C is an object-oriented language similar to Java, designed specifically for resource-constrained wearables. It's dynamically typed (with optional type annotations), garbage collected, and supports classes and inheritance. Watch faces extend `WatchUi.WatchFace` and implement key callbacks: `onLayout()` for initial setup, `onUpdate()` for drawing (called every minute in low-power mode, every second in high-power mode), and `onPartialUpdate()` for efficient always-on display updates.

A minimal watch face view looks like this:

```monkeyc
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;

class MyWatchFaceView extends WatchUi.WatchFace {
    function initialize() {
        WatchFace.initialize();
    }
    
    function onUpdate(dc) {
        var clockTime = System.getClockTime();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth()/2, dc.getHeight()/2, Graphics.FONT_LARGE,
            Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%02d")]),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
```

Create new projects using the VS Code command palette: `Monkey C: New Project`, select "Watch Face" as the project type, choose API level 5.2 for Forerunner 965 compatibility, and include `fr965` in your target devices.

---

## Testing in the simulator and deploying to your watch

Building and running in the simulator is as simple as pressing **F5** in VS Code. The simulator provides a realistic preview of your watch face, lets you test different time formats, simulate low battery states, and view console output from `System.println()` debug statements. The simulator's memory viewer (File → View Memory) is essential for monitoring your app's memory usage during development.

To deploy to your actual Forerunner 965, use the command `Monkey C: Build for Device`, select the FR965 as your target, and export a `.prg` file. Connect your watch via USB (wait ~30 seconds for it to mount as an external drive), copy the `.prg` file to the `GARMIN/Apps/` directory, safely eject the watch, and select your new watch face from the watch settings. Note that you cannot debug directly on the physical device—the watch must be disconnected to run sideloaded apps.

For crash analysis, check the `GARMIN/Logs/CIQ_LOG.txt` file on your watch after encountering errors. Garmin also provides an Exception Reporting tool and ERA Viewer for analyzing crash reports from published apps.

---

## Forerunner 965 capabilities and technical constraints

The Forerunner 965 is a top-tier Connect IQ device with generous specifications. The display is a **1.4-inch round AMOLED** at **454×454 pixels** supporting **24-bit color** (16.7 million colors). It runs Connect IQ **API Level 5.2** and has **GPU-accelerated graphics** for anti-aliasing and bitmap transformations. The device ID for your manifest is `fr965`.

Watch faces on the FR965 have approximately **512 KB of memory** available, with background services limited to **~64 KB**. This is substantially more than older devices (the Fenix 5 had only 92 KB for watch faces). Your compiled code, fonts, bitmaps, and localization strings all count toward this limit. Exceeding it causes the app to crash and the default watch face to display. Best practices include pre-calculating values in `onLayout()` rather than `onUpdate()`, caching computed values, and using system fonts where possible.

Watch faces operate in distinct power modes. **High-power mode** is triggered by wrist gestures and lasts about 10 seconds, during which `onUpdate()` is called every second and animations are possible. **Low-power mode** calls `onUpdate()` only once per minute, though `onPartialUpdate()` can be called every second for efficient always-on display updates—but you must use clipping regions and keep execution under 30ms average to stay within the power budget.

---

## What watch faces can and cannot access

Watch faces can access a rich set of data through the Connect IQ API. The **ActivityMonitor module** provides steps, calories, distance, floors climbed, active minutes, and move bar levels. **SensorHistory** gives access to historical heart rate, temperature, pressure, elevation, SpO2, stress, and Body Battery data. **UserProfile** contains height, weight, age, resting heart rate, and sleep times. The **Weather module** (since CIQ 3.2) provides current conditions including temperature, humidity, wind, and precipitation.

However, watch faces have significant restrictions compared to full device apps. They **cannot make direct web requests**—HTTP calls must go through a background service that can run at minimum 5-minute intervals. They **cannot access live GPS**—only the last known position via static calls. They **cannot play sounds or trigger vibration**, cannot run timers or animations in low-power mode, and cannot access the content of phone notifications (only the count). These restrictions are fundamental to the watch face architecture and cannot be circumvented.

For graphics, the `Graphics.Dc` class provides comprehensive drawing capabilities: lines, circles, ellipses, arcs, rectangles, polygons (up to 64 points), and scaled bitmaps. Text can be drawn with various justifications, and on API 4.2.1+ devices like the FR965, you can draw angled and radial text using vector fonts. Anti-aliasing is GPU-accelerated on the FR965. Custom fonts must be in BMFont format (.fnt + .png files), and bitmap resources must be PNG format compiled into the app.

---

## Publishing to Connect IQ Store is free and takes up to three days

Publishing a watch face involves exporting an `.iq` file using the VS Code command `Monkey C: Export Project`, then uploading it to the developer portal at **apps-developer.garmin.com**. You'll need a **500×500 pixel app icon** (PNG or JPG, max 150KB, sRGB color space) and **500×500 pixel screenshots**. Optionally, you can provide a 128×128 on-device icon and a 1440×720 hero image for store prominence.

The review process takes **up to 3 days for initial submissions** and approximately **2 hours for updates**. Garmin performs automated security scans and content reviews. Common rejection reasons include app crashes, copyright violations (watch faces mimicking luxury watch brands like Rolex are explicitly prohibited), inappropriate content, and GPS data usage violations. Apps requiring payment must be clearly marked, and medical apps need FDA documentation or educational-purposes disclaimers.

**All costs are zero for free apps.** The developer account is free, the SDK is free, publishing is free, and reviews are free. Only if you want to sell apps through Garmin's monetization system do fees apply: a **$100/year merchant onboarding fee** plus **15% revenue share**. Many developers use alternative approaches like linking to external payment sites or requesting donations, which is permitted as long as you mark "Payment Required" in your listing.

---

## Open sourcing your watch face is explicitly allowed

Garmin's Connect IQ Developer Agreement prohibits redistributing the **SDK itself** (compiler, simulators, documentation), but your Monkey C source code remains your intellectual property. The agreement explicitly states that "Garmin shall not acquire any ownership interest in or to your Application." You can open source under any license you choose—MIT, GPL-3.0, Apache 2.0, or others.

The community has embraced open source development. The **Crystal watch face** (github.com/warmsound/crystal-face) is the gold standard example with **445 stars, 137 forks**, and over 2 million downloads on the Connect IQ Store, licensed under GPL-3.0. The Garmin Forums maintain a pinned thread listing open source Connect IQ apps with source code, and GitHub's `garmin-watch-face` and `garmin-connect-iq` topics contain hundreds of repositories.

Best practices for open source Garmin projects include including a clear LICENSE file (GPL-3.0 is the community standard for watch faces), a comprehensive README with build instructions and device compatibility, proper attribution for third-party icons and fonts, and links to your Connect IQ Store listing. You **cannot** redistribute the SDK, Garmin's documentation, device simulators, or use Garmin trademarks without written permission.

---

## Complete toolkit for watch face development

The essential development stack consists of:

- **Programming language:** Monkey C (Garmin's proprietary object-oriented language)
- **SDK:** Connect IQ SDK 8.4.0 (December 2025)
- **IDE:** Visual Studio Code with official Monkey C extension
- **Design tools:** BMFont for custom fonts, any image editor for PNG assets
- **Testing:** Built-in simulator with device profiles
- **Debugging:** `System.println()` output, VS Code Debug Console, CIQ_LOG.txt on device

For graphics design, create assets in any image editor that exports PNG files. Icons should be 500×500 pixels for the store and 128×128 pixels for on-device display. Watch face previews work best when framed with a watch bezel for context. For custom fonts, use the BMFont tool (Windows) to generate .fnt files with only the characters you need to minimize memory usage.

Official resources to bookmark:
- **Developer portal:** developer.garmin.com
- **SDK download:** developer.garmin.com/connect-iq/sdk/
- **API documentation:** developer.garmin.com/connect-iq/api-docs/
- **Compatible devices:** developer.garmin.com/connect-iq/compatible-devices/
- **VS Code extension:** marketplace.visualstudio.com/items?itemName=garmin.monkey-c
- **Developer forums:** forums.garmin.com/developer/connect-iq/
- **Submission portal:** apps-developer.garmin.com
- **Brand guidelines:** developer.garmin.com/brand-guidelines/connect-iq/

---

## Conclusion

Building a custom watch face for the Garmin Forerunner 965 is a well-supported, completely free endeavor with mature tooling and an active community. The development workflow—VS Code, Monkey C, and the simulator—enables rapid iteration, while the FR965's 512 KB memory limit and AMOLED display provide substantial creative freedom compared to older devices. The three key technical constraints to design around are the minute-by-minute update cycle in low-power mode, the requirement to use background services for web requests, and the prohibition on direct GPS access.

Most developers can have a functional watch face running in the simulator within an afternoon, with device testing following shortly after. Publishing approval typically takes 1-3 days, and open sourcing your creation is not only permitted but encouraged by a community that has made projects like Crystal watch face freely available as learning resources. The path from "no Garmin developer account" to "published watch face" is measured in days, not weeks.
