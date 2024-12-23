# Japanese Comic Translator

This is a macOS app that allows you to translate Japanese text in comic images.  Made in a few hours with Cursor.

## Usage

1. Open the app
2. Select an image or a directory of images
3. Click "Translate"
4. The translated image will be saved to the same directory as the original image

## Requirements

- macOS 15+ (Translate API requires macOS 15+)
- Xcode 16.2+
- Tuist

## Known issues

- You can only do a translation of a directory or image once before needing to restart the app.  TranslationTask doesn't seem to be liked to be used more than once and you can't get it starting again in the same view.  If you don't make the config nil, then it repeats the translation over and over.  Needs to be figured out.  Maybe a processing queue design for the `TranslateWorker` so even if apple's code goes into an infinite loop, at least it will be a Noop 🙄.
- iOS support is untested.
- I haven't tested downloading local models from the Translate API UI and permissions to do translation.
- Can't make this a command line tool since apple forces API usage through a SwiftUI only design.

## Next features

[ ] Choose original input language (ex: Japanese, English, Chinese, French, Korean, autodetect, etc.)
[ ] Choose output language (and detect if a string is already in the output language beyond my hack for english to skip translation)
[ ] Fix known issues
[ ] Stop button

## Wishful next features

These are features I want, but I'm not sure if they are easy to implement.

[ ] Merge boxes automatically (two lines of the same sentence show up as two boxes, which make nonsensical sentences, something to merge close together boxes logically, also support vertical writing support for jp)
[ ] Make the bounding box detection follow the orientation of the text, so instead of a simple rectangle, it would be a rotated rectangle.  Or a polygon.
[ ] Support fancy manga style text, like sound effects, fancy titles, etc.
[ ] Auto-detect language of the text
[ ] Make this a browser extension for full local translation of images.  Make it run automatically with images beyond a certain size on a white list of pages. 
[ ] Make the text overlays match the background style of the original text and clean out the original text itself.


