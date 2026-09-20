# Meet PaperBridge Video

## Status and scope

The optimized commercial was approved after local playback on September 20,
2026. The user confirmed that the homepage and marketing page mean the same
public page at `/`.

The video is uploaded and publicly readable from the dedicated media bucket.
Unsigned HTTPS access and byte-range requests were verified on September 20,
2026. The homepage implementation opens that video in a native dialog from the
existing "Meet PaperBridge" hero action.

## Approved video

- Local file: `/home/josh/Downloads/commercial-web.mp4`.
- Size: 27,180,876 bytes, reduced from 698,163,862 bytes.
- Picture: 1920 x 1080, H.264, approximately 23.976 frames per second.
- Sound: stereo AAC, 48 kHz, approximately 160 kbps.
- Duration: approximately 96 seconds. All 2,304 original video frames remain.
- MP4 metadata is at the start of the file for progressive playback.
- A full video/audio decode check passed; the user confirmed picture and sound
  in FFplay. GNOME Videos failed to open both the original and optimized files.
- SHA-256: `82ab1d5c3ac6ab59e8b50f90aaca506598346bb0ec3d20f2c030c9d912a65e66`.

## Published S3 video

Live inspection confirmed that `paper-bridge-production` blocks all public
access, disables ACLs with `BucketOwnerEnforced`, and has no bucket policy.
Keep those protections and the existing Active Storage configuration intact.

The user approved creating a dedicated bucket in the existing AWS account:

- Bucket: `paper-bridge-public-media`, region `us-east-1`.
- Object key: `marketing/meet-paperbridge-v1.mp4`.
- Public URL: [Play Meet PaperBridge](https://paper-bridge-public-media.s3.us-east-1.amazonaws.com/marketing/meet-paperbridge-v1.mp4).
- Content type: `video/mp4`; disposition: `inline`.
- Cache control: `public, max-age=31536000, immutable`. Future replacements get
  a new versioned filename so caches cannot serve stale content.
- Encryption: S3-managed AES256. Keep ACLs disabled.
- Anonymous `s3:GetObject` is allowed for this exact object only. Public listing,
  uploads, deletion, and access to other object paths are not granted.
- Public access blocks on the media bucket are `BlockPublicAcls: true`,
  `IgnorePublicAcls: true`, `BlockPublicPolicy: true`, and
  `RestrictPublicBuckets: false`. During setup, `BlockPublicPolicy` was
  temporarily disabled to install the exact public-read policy, then restored.
  Future intentional public-policy changes require the same temporary change.
- No account-level public-access settings or customer-storage bucket settings
  were changed.

The exact public permission is:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadMeetPaperBridgeVideo",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::paper-bridge-public-media/marketing/meet-paperbridge-v1.mp4"
  }]
}
```

Publication checks passed:

- S3 returned the same SHA-256 checksum and byte count as the local video.
- Unsigned HTTPS `HEAD`: `200`, `video/mp4`, 27,180,876 bytes, `Accept-Ranges:
  bytes`, and the expected cache-control value.
- Unsigned requests for bytes `0-1023` and `16000000-16001023`: `206`, correct
  content ranges, and bytes identical to the local file.
- Anonymous bucket listing: `403`.
- All four public-access blocks on `paper-bridge-production` remained enabled.

These are storage and delivery checks. Browser checks are described below.

AWS documents the interaction of existing policies and public-access blocks in
[Blocking public access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html).

## Homepage behavior

- `app/views/home/index.html.erb` keeps the existing hero action's label, icon,
  and styling. It opens the video dialog with JavaScript and links directly to
  the MP4 without JavaScript or when opening the link in a new tab. How It
  Works retains its own navigation link and section.
- `app/views/home/_marketing_video.html.erb` provides a native `<dialog>` with
  an accessible title, a close button, and a responsive 16:9 video player.
  Native controls provide playback, volume, seeking, and fullscreen;
  `playsinline` supports playback within the page on phones.
- `marketing_video_controller.js` sets the video source only after a click and
  attempts playback immediately. If the browser declines that attempt, the
  native play control remains available. No video downloads or plays on page
  load.
- Close, Escape, and backdrop clicks dismiss the dialog. Closing pauses the
  video, removes its source to release playback and pending loading, and
  returns focus to the trigger. Reopening starts from the beginning. Turbo
  cache and controller disconnect also clean up the player and scroll lock.
- `HomeHelper#meet_paperbridge_video_url` supplies the one public URL for the
  trigger, player, and direct-video fallback in every environment. There is no
  database record, customer-document upload, new route, or processing job.
- Loading failures show a short message and a link to open the video directly.
  Captions were not supplied with the commercial; this implementation does
  not add a captions track.

## Validation

The existing homepage tests cover guest and signed-in entry actions and the
public video URL. Focused commands:

```bash
bin/rails test test/controllers/home_controller_test.rb
ruby scripts/check_docs_index.rb
```

For this small interaction, use a direct browser check rather than maintaining
a separate JavaScript test suite. Check actual S3 playback, audio, and seeking
at desktop and phone widths; confirm the video does not load before a click,
all dismissal paths stop playback, keyboard focus returns to the trigger, and
navigation does not leave the video playing. Check the direct link without
JavaScript and the error fallback when changing the player.

On September 20, 2026, the actual public S3 video was verified in Chromium at
1280 x 900 and 390 x 844: no media request before clicking, 1080p playback with
audio decoding, seeking to 36 seconds, and paused/reset playback with focus
restored after closing. Neither browser run reported JavaScript or console
errors.

The existing public-home browser smoke test remains available through the QA
harness. Run the product `review` harness before committing broader product
changes, as required by `AGENTS.md`.
