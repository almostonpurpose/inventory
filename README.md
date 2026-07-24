# HomeInventory

A native SwiftUI iPhone app for building a home inventory and assistant-ready house memory from photo sweeps or walkthrough videos.

See [HANDOFF.md](HANDOFF.md) for the current architecture notes, known detector limitation, and recommended next steps for live YOLO scanning.

## What it does

- Captures in-app photo sweeps without saving source photos, or imports existing photos/walkthrough videos.
- Uses scan missions such as room sweep, pantry, fridge, wardrobe, drawer, toolbox, toys, and close-up.
- Stores room, shelf/zone, and container context so items are findable later.
- Samples frames from the video with AVFoundation.
- Uses Ultralytics YOLO/Core ML for object boxes and first-pass object labels.
- Uses Apple's Vision framework as a fallback for saliency crops and for OCR/barcode metadata.
- Groups photo/frame crop-level findings into editable object cards with photos.
- Saves reviewed items into a local JSON store on the device.
- Supports search, category filtering, manual item entry, item editing, condition, expiry dates, restock thresholds, replacement hints, metadata, and detail-scan flags.
- Maintains an assistant event stream and exportable assistant snapshot JSON for cooking, restocking, organizing, and finding-stuff workflows.
- Exports a laptop review JSON package with low-confidence/detail-scan item crops embedded as base64 JPEGs for heavier off-device classification.
- Treats source photos/videos as temporary; in-app source photos stay in memory only, and only item crops plus reviewed records are retained.

## Build

1. Generate the Xcode project:

   ```sh
   xcodegen generate
   ```

2. Open `HomeInventory.xcodeproj`.
3. Select your development team in Signing & Capabilities.
4. Choose your iPhone as the run destination.
5. Build and run.

## Notes

This version is intentionally local-first after setup. It does not need an account, backend, or API key. The first YOLO run downloads and caches the official nano Core ML detection model from Ultralytics unless you later bundle a model in the app. The review screen is still the source of truth before anything is added to the inventory.

The data model is designed so a later laptop or desktop classifier can reprocess tricky items. Items marked as needing detail scans, plus the laptop review package, assistant snapshot, and event stream, are the handoff points for heavier off-device analysis.

LiDAR/ARKit room mapping is not implemented yet. It may help with spatial placement later, but it is not expected to improve object classification as much as YOLO or a laptop vision-language pass.
