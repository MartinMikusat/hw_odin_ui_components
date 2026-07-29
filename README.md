# Odin UI Components

Reusable, renderer-independent interaction components for Odin applications.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**

Each component is a separate package below this repository. Applications add
the repository as an Odin collection and import only the packages they use.

```odin
import text_input "components:text_input"
```

## Text input

`text_input` owns one active editing session. Application strings remain
application-owned. The session tracks:

- the active field identifier;
- UTF-8 caret and selection byte offsets;
- IME marked text and UTF-16 AppKit ranges;
- pointer drag selection;
- horizontal caret scrolling.

The package implements editing operations and returns state changes. It does
not register Objective-C classes, access the pasteboard, measure fonts, draw
controls, or execute application actions.

Applications must route focused keyboard input through `NSTextInputClient` and
AppKit `interpretKeyEvents`. Applications translate AppKit selectors into the
package editing operations, then run their own change or submit action.

Applications calculate CoreText advances and pass the measured caret position
to `update_horizontal_scroll`. They draw the returned caret and selection
ranges with their own theme.

## Verification

```sh
./test.sh
```

## License

This repository uses the MIT license. See [LICENSE](LICENSE).
