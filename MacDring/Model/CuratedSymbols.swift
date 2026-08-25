import Foundation

/// The curated set of SF Symbol names the symbol picker offers as tab glyphs, factored
/// out of the (macOS-only, SwiftUI) `SymbolPickerView` so the platform-neutral icon
/// layer — and the test that asserts every one has a Linux mapping — can reach it on
/// both platforms. `SymbolPickerView.symbols` is this list. See PLAN.md §LP-13.
enum CuratedSymbols {
    /// A large curated set of SF Symbols useful for labeling drawers.
    static let all: [String] = [
        // Files & folders
        "folder", "folder.fill", "folder.badge.plus", "folder.badge.gearshape", "doc", "doc.fill",
        "doc.text", "doc.text.fill", "doc.on.doc", "doc.on.doc.fill", "doc.richtext", "doc.plaintext",
        "doc.zipper", "note.text", "list.bullet", "list.bullet.rectangle", "list.number",
        "tray", "tray.fill", "tray.full", "tray.full.fill", "tray.2", "tray.2.fill",
        "archivebox", "archivebox.fill", "externaldrive", "externaldrive.fill", "internaldrive",
        // Grids & windows
        "square.grid.2x2", "square.grid.2x2.fill", "square.grid.3x3", "square.grid.3x3.fill",
        "rectangle.grid.2x2", "rectangle.stack", "rectangle.stack.fill", "square.stack", "square.stack.fill",
        "app", "app.fill", "macwindow", "macwindow.on.rectangle", "dock.rectangle",
        "sidebar.left", "sidebar.right", "square.split.2x1", "squares.below.rectangle",
        // Tools & editing
        "hammer", "hammer.fill", "wrench", "wrench.fill", "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
        "screwdriver", "screwdriver.fill", "gearshape", "gearshape.fill", "gearshape.2", "gearshape.2.fill",
        "slider.horizontal.3", "slider.vertical.3", "ruler", "ruler.fill",
        "paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintbrush.pointed.fill", "paintpalette", "paintpalette.fill",
        "pencil", "pencil.tip", "pencil.and.outline", "eraser", "eraser.fill", "highlighter", "scissors",
        "paperclip", "link", "link.circle", "terminal", "terminal.fill", "curlybraces", "command", "option",
        "textformat", "textformat.size", "bold", "italic", "underline",
        // Media
        "play", "play.fill", "play.circle", "play.circle.fill", "pause", "pause.fill", "stop.fill",
        "music.note", "music.note.list", "music.mic", "headphones", "speaker.wave.2", "speaker.wave.2.fill",
        "film", "film.fill", "video", "video.fill", "tv", "tv.fill", "photo", "photo.fill", "photo.on.rectangle",
        "camera", "camera.fill", "camera.viewfinder", "mic", "mic.fill", "waveform",
        "gamecontroller", "gamecontroller.fill", "dpad", "dpad.fill",
        // Communication & people
        "envelope", "envelope.fill", "envelope.open", "paperplane", "paperplane.fill",
        "message", "message.fill", "bubble.left", "bubble.left.fill", "bubble.right.fill",
        "phone", "phone.fill", "phone.circle", "at",
        "person", "person.fill", "person.2", "person.2.fill", "person.3.fill", "person.crop.circle", "person.crop.circle.fill",
        "bell", "bell.fill", "bell.badge", "bell.badge.fill",
        // Web, cloud, transfer
        "globe", "globe.americas.fill", "network", "wifi", "wifi.circle", "antenna.radiowaves.left.and.right",
        "icloud", "icloud.fill", "cloud", "cloud.fill", "cloud.rain.fill", "server.rack",
        "arrow.up.arrow.down", "arrow.triangle.2.circlepath", "arrow.clockwise", "arrow.counterclockwise",
        "square.and.arrow.up", "square.and.arrow.up.fill", "square.and.arrow.down", "square.and.arrow.down.fill",
        // Symbols & shapes
        "star", "star.fill", "star.circle.fill", "heart", "heart.fill", "bolt", "bolt.fill", "flame", "flame.fill",
        "leaf", "leaf.fill", "drop", "drop.fill", "sparkles", "wand.and.stars",
        "sun.max", "sun.max.fill", "moon", "moon.fill", "moon.stars.fill", "cloud.sun.fill", "snowflake",
        "flag", "flag.fill", "flag.checkered", "tag", "tag.fill", "bookmark", "bookmark.fill", "pin", "pin.fill",
        "mappin", "map", "map.fill", "location", "location.fill",
        "circle", "circle.fill", "square", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill",
        "seal", "seal.fill", "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.seal.fill",
        "xmark", "xmark.circle.fill", "plus", "plus.circle", "plus.circle.fill", "minus.circle",
        "exclamationmark.triangle", "exclamationmark.triangle.fill", "questionmark.circle", "info.circle", "info.circle.fill",
        // Objects
        "house", "house.fill", "building", "building.fill", "building.2", "building.2.fill", "building.columns.fill",
        "cart", "cart.fill", "bag", "bag.fill", "basket.fill", "creditcard", "creditcard.fill",
        "banknote.fill", "dollarsign.circle", "gift", "gift.fill", "shippingbox", "shippingbox.fill",
        "briefcase", "briefcase.fill", "suitcase.fill", "book", "book.fill", "books.vertical.fill",
        "graduationcap", "graduationcap.fill", "backpack",
        "trash", "trash.fill", "lock", "lock.fill", "lock.open", "lock.shield", "key", "key.fill",
        "shield", "shield.fill", "eye", "eye.fill", "eye.slash", "hand.raised.fill", "hand.thumbsup.fill",
        // Time
        "calendar", "calendar.badge.clock", "clock", "clock.fill", "alarm", "alarm.fill",
        "stopwatch", "stopwatch.fill", "timer", "hourglass",
        // Devices
        "desktopcomputer", "laptopcomputer", "display", "keyboard", "computermouse", "computermouse.fill",
        "iphone", "ipad", "applewatch", "printer", "printer.fill", "homepod.fill",
        // Charts & misc
        "magnifyingglass", "magnifyingglass.circle", "line.3.horizontal", "line.3.horizontal.decrease",
        "ellipsis", "ellipsis.circle", "chart.bar", "chart.bar.fill", "chart.pie.fill", "chart.line.uptrend.xyaxis",
        "function", "percent", "number", "qrcode", "barcode", "lightbulb", "lightbulb.fill", "powerplug.fill",
        // Transport & nature
        "car", "car.fill", "bus.fill", "tram.fill", "bicycle", "airplane", "fuelpump.fill", "figure.walk",
        "tortoise.fill", "hare.fill", "ant.fill", "ladybug.fill", "pawprint", "pawprint.fill", "fish.fill",
        "bird.fill", "tree", "mountain.2.fill", "wind", "thermometer.sun.fill",
    ]
}
