import Foundation

/// SF Symbol → Linux-icon-set name mapping (LP-13). The Linux set is **Lucide**
/// (https://lucide.dev, ISC/MIT-licensed) — a single coherent open set with broad,
/// well-named coverage. This is mechanical data seeded for every symbol in
/// `CuratedSymbols.all` plus a few names the code references directly; `IconNameTests`
/// asserts the curated list is fully covered. Where SF has no clean Lucide analogue a
/// nearby glyph is chosen, and any symbol not listed here falls back to
/// `IconName.genericLinuxIcon`. Names use Lucide's current (post-rename) inventory and
/// are best-effort; the actual Linux rendering that consumes them is a later LP. When it
/// lands, pin the bundled Lucide version and add a test asserting every value below
/// exists in it (an unknown name would silently degrade to the generic fallback). See
/// PLAN.md §LP-13.
enum IconMap {
    static let linux: [String: String] = [
        // Files & folders
        "folder": "folder", "folder.fill": "folder", "folder.badge.plus": "folder-plus",
        "folder.badge.gearshape": "folder-cog", "doc": "file", "doc.fill": "file",
        "doc.text": "file-text", "doc.text.fill": "file-text", "doc.on.doc": "files",
        "doc.on.doc.fill": "files", "doc.richtext": "file-type", "doc.plaintext": "file-text",
        "doc.zipper": "file-archive", "note.text": "notebook-text", "list.bullet": "list",
        "list.bullet.rectangle": "list", "list.number": "list-ordered",
        "tray": "inbox", "tray.fill": "inbox", "tray.full": "inbox", "tray.full.fill": "inbox",
        "tray.2": "inbox", "tray.2.fill": "inbox", "archivebox": "archive", "archivebox.fill": "archive",
        "externaldrive": "hard-drive", "externaldrive.fill": "hard-drive", "internaldrive": "hard-drive",
        // Grids & windows
        "square.grid.2x2": "grid-2x2", "square.grid.2x2.fill": "grid-2x2", "square.grid.3x3": "grid-3x3",
        "square.grid.3x3.fill": "grid-3x3", "rectangle.grid.2x2": "layout-grid", "rectangle.stack": "layers",
        "rectangle.stack.fill": "layers", "square.stack": "layers", "square.stack.fill": "layers",
        "app": "app-window", "app.fill": "app-window", "macwindow": "app-window",
        "macwindow.on.rectangle": "app-window", "dock.rectangle": "panel-bottom",
        "sidebar.left": "panel-left", "sidebar.right": "panel-right", "square.split.2x1": "columns-2",
        "squares.below.rectangle": "layout-grid",
        // Tools & editing
        "hammer": "hammer", "hammer.fill": "hammer", "wrench": "wrench", "wrench.fill": "wrench",
        "wrench.and.screwdriver": "wrench", "wrench.and.screwdriver.fill": "wrench",
        "screwdriver": "screwdriver", "screwdriver.fill": "screwdriver", "gearshape": "settings",
        "gearshape.fill": "settings", "gearshape.2": "settings-2", "gearshape.2.fill": "settings-2",
        "slider.horizontal.3": "sliders-horizontal", "slider.vertical.3": "sliders-vertical",
        "ruler": "ruler", "ruler.fill": "ruler", "paintbrush": "paintbrush", "paintbrush.fill": "paintbrush",
        "paintbrush.pointed": "brush", "paintbrush.pointed.fill": "brush", "paintpalette": "palette",
        "paintpalette.fill": "palette", "pencil": "pencil", "pencil.tip": "pen", "pencil.and.outline": "pencil-line",
        "eraser": "eraser", "eraser.fill": "eraser", "highlighter": "highlighter", "scissors": "scissors",
        "paperclip": "paperclip", "link": "link", "link.circle": "link", "terminal": "terminal",
        "terminal.fill": "terminal", "curlybraces": "braces", "command": "command", "option": "option",
        "textformat": "type", "textformat.size": "type", "bold": "bold", "italic": "italic", "underline": "underline",
        // Media
        "play": "play", "play.fill": "play", "play.circle": "play", "play.circle.fill": "play",
        "pause": "pause", "pause.fill": "pause", "stop.fill": "square", "music.note": "music",
        "music.note.list": "list-music", "music.mic": "mic", "headphones": "headphones",
        "speaker.wave.2": "volume-2", "speaker.wave.2.fill": "volume-2", "film": "film", "film.fill": "film",
        "video": "video", "video.fill": "video", "tv": "tv", "tv.fill": "tv", "photo": "image",
        "photo.fill": "image", "photo.on.rectangle": "images", "camera": "camera", "camera.fill": "camera",
        "camera.viewfinder": "scan", "mic": "mic", "mic.fill": "mic", "waveform": "audio-waveform",
        "gamecontroller": "gamepad-2", "gamecontroller.fill": "gamepad-2", "dpad": "gamepad", "dpad.fill": "gamepad",
        // Communication & people
        "envelope": "mail", "envelope.fill": "mail", "envelope.open": "mail-open", "paperplane": "send",
        "paperplane.fill": "send", "message": "message-square", "message.fill": "message-square",
        "bubble.left": "message-circle", "bubble.left.fill": "message-circle", "bubble.right.fill": "message-circle",
        "phone": "phone", "phone.fill": "phone", "phone.circle": "phone", "at": "at-sign",
        "person": "user", "person.fill": "user", "person.2": "users", "person.2.fill": "users",
        "person.3.fill": "users", "person.crop.circle": "circle-user", "person.crop.circle.fill": "circle-user",
        "bell": "bell", "bell.fill": "bell", "bell.badge": "bell-dot", "bell.badge.fill": "bell-dot",
        // Web, cloud, transfer
        "globe": "globe", "globe.americas.fill": "globe", "network": "network", "wifi": "wifi",
        "wifi.circle": "wifi", "antenna.radiowaves.left.and.right": "radio", "icloud": "cloud",
        "icloud.fill": "cloud", "cloud": "cloud", "cloud.fill": "cloud", "cloud.rain.fill": "cloud-rain",
        "server.rack": "server", "arrow.up.arrow.down": "arrow-up-down",
        "arrow.triangle.2.circlepath": "refresh-cw", "arrow.clockwise": "rotate-cw",
        "arrow.counterclockwise": "rotate-ccw", "square.and.arrow.up": "share", "square.and.arrow.up.fill": "share",
        "square.and.arrow.down": "download", "square.and.arrow.down.fill": "download",
        // Symbols & shapes
        "star": "star", "star.fill": "star", "star.circle.fill": "star", "heart": "heart", "heart.fill": "heart",
        "bolt": "zap", "bolt.fill": "zap", "flame": "flame", "flame.fill": "flame", "leaf": "leaf",
        "leaf.fill": "leaf", "drop": "droplet", "drop.fill": "droplet", "sparkles": "sparkles",
        "wand.and.stars": "wand-sparkles", "sun.max": "sun", "sun.max.fill": "sun", "moon": "moon",
        "moon.fill": "moon", "moon.stars.fill": "moon-star", "cloud.sun.fill": "cloud-sun", "snowflake": "snowflake",
        "flag": "flag", "flag.fill": "flag", "flag.checkered": "flag", "tag": "tag", "tag.fill": "tag",
        "bookmark": "bookmark", "bookmark.fill": "bookmark", "pin": "pin", "pin.fill": "pin", "mappin": "map-pin",
        "map": "map", "map.fill": "map", "location": "locate", "location.fill": "locate",
        "circle": "circle", "circle.fill": "circle", "square": "square", "square.fill": "square",
        "triangle.fill": "triangle", "diamond.fill": "diamond", "hexagon.fill": "hexagon",
        "seal": "badge", "seal.fill": "badge", "checkmark": "check", "checkmark.circle": "circle-check",
        "checkmark.circle.fill": "circle-check", "checkmark.seal.fill": "badge-check", "xmark": "x",
        "xmark.circle.fill": "circle-x", "plus": "plus", "plus.circle": "circle-plus",
        "plus.circle.fill": "circle-plus", "minus.circle": "circle-minus",
        "exclamationmark.triangle": "triangle-alert", "exclamationmark.triangle.fill": "triangle-alert",
        "questionmark.circle": "circle-help", "info.circle": "info", "info.circle.fill": "info",
        // Objects
        "house": "house", "house.fill": "house", "building": "building", "building.fill": "building",
        "building.2": "building-2", "building.2.fill": "building-2", "building.columns.fill": "landmark",
        "cart": "shopping-cart", "cart.fill": "shopping-cart", "bag": "shopping-bag", "bag.fill": "shopping-bag",
        "basket.fill": "shopping-basket", "creditcard": "credit-card", "creditcard.fill": "credit-card",
        "banknote.fill": "banknote", "dollarsign.circle": "circle-dollar-sign", "gift": "gift", "gift.fill": "gift",
        "shippingbox": "package", "shippingbox.fill": "package", "briefcase": "briefcase",
        "briefcase.fill": "briefcase", "suitcase.fill": "luggage", "book": "book", "book.fill": "book",
        "books.vertical.fill": "library", "graduationcap": "graduation-cap", "graduationcap.fill": "graduation-cap",
        "backpack": "backpack", "trash": "trash-2", "trash.fill": "trash-2", "lock": "lock", "lock.fill": "lock",
        "lock.open": "lock-open", "lock.shield": "shield", "key": "key", "key.fill": "key", "shield": "shield",
        "shield.fill": "shield", "eye": "eye", "eye.fill": "eye", "eye.slash": "eye-off", "hand.raised.fill": "hand",
        "hand.thumbsup.fill": "thumbs-up",
        // Time
        "calendar": "calendar", "calendar.badge.clock": "calendar-clock", "clock": "clock", "clock.fill": "clock",
        "alarm": "alarm-clock", "alarm.fill": "alarm-clock", "stopwatch": "timer", "stopwatch.fill": "timer",
        "timer": "timer", "hourglass": "hourglass",
        // Devices
        "desktopcomputer": "monitor", "laptopcomputer": "laptop", "display": "monitor", "keyboard": "keyboard",
        "computermouse": "mouse", "computermouse.fill": "mouse", "iphone": "smartphone", "ipad": "tablet",
        "applewatch": "watch", "printer": "printer", "printer.fill": "printer", "homepod.fill": "speaker",
        // Charts & misc
        "magnifyingglass": "search", "magnifyingglass.circle": "search", "line.3.horizontal": "menu",
        "line.3.horizontal.decrease": "list-filter", "ellipsis": "ellipsis", "ellipsis.circle": "circle-ellipsis",
        "chart.bar": "chart-column", "chart.bar.fill": "chart-column", "chart.pie.fill": "chart-pie",
        "chart.line.uptrend.xyaxis": "chart-line", "function": "square-function", "percent": "percent",
        "number": "hash", "qrcode": "qr-code", "barcode": "barcode", "lightbulb": "lightbulb",
        "lightbulb.fill": "lightbulb", "powerplug.fill": "plug",
        // Transport & nature
        "car": "car", "car.fill": "car", "bus.fill": "bus", "tram.fill": "tram-front", "bicycle": "bike",
        "airplane": "plane", "fuelpump.fill": "fuel", "figure.walk": "footprints", "tortoise.fill": "turtle",
        "hare.fill": "rabbit", "ant.fill": "bug", "ladybug.fill": "bug", "pawprint": "paw-print",
        "pawprint.fill": "paw-print", "fish.fill": "fish", "bird.fill": "bird", "tree": "tree-deciduous",
        "mountain.2.fill": "mountain", "wind": "wind", "thermometer.sun.fill": "thermometer-sun",

        // Code-referenced symbols not in the picker's curated grid
        "questionmark.square.dashed": "circle-help",   // SymbolPickerView's empty-selection placeholder
        "square.grid.2x2.fill.badge.ellipsis": "grid-2x2",
    ]
}
