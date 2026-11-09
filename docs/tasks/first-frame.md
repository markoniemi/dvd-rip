---
id: first-frame
status: planned
priority: medium
kind: task
branch: task/first-frame
---

# first frame

Windows and many applications show videos as icons, and show first frame as
icon. Is it possible to set the poster image as first frame or video?

# Implementation Plan

## Where the pipeline stands

`ConvertNext.ps1` already does two things with the poster
(`Add-PosterArt`, `Scripts/ConvertNext.ps1:333`):

* copies the raw folder's image next to the converted mkv as a sidecar
  (`I:\Video\Ready\Amelie.jpg` beside `Amelie.mkv`), and
* attaches it inside the mkv as a `cover.jpg`/`cover.png` attachment with
  `mkvpropedit` (`Set-CoverArt`, `Scripts/ConvertNext.ps1:279`).

Plex and Jellyfin read both. Windows Explorer reads neither: a Matroska
attachment is not a shell thumbnail, and Explorer never looks at a sidecar
image for a video file. So the poster is already everywhere a media server
looks, and nowhere the file manager looks. That is the whole gap.

## What Windows actually does, and what the question assumes

The premise — "Windows shows the first frame" — is close but not exact, and
the difference decides whether this task is even worth code:

* Explorer asks a registered thumbnail provider for the extension. For
  `.mkv` on a stock Windows 10/11 that means Media Foundation **decoding a
  frame**, which needs the HEVC codec extension installed for our H.265
  output, or no thumbnail appears at all.
* Which frame is not documented. Reports say "the opening frame"; other
  providers deliberately avoid frame 0 because it is often black
  (SageThumbs grabs ~30% in; a provider's own default is frame 4). So
  "make frame 0 the poster" does not reliably mean "Explorer shows the
  poster".
* Nothing in Matroska carries a thumbnail Windows reads. Third-party
  providers (Icaros, SageThumbs) can prefer an embedded cover attachment,
  but only after a per-machine install plus a thumbnail-cache clear.
* MP4 is the exception: iTunes-style cover art (`moov/udta/meta/ilst/covr`)
  is reported to be read by Explorer's MP4 property handler with no decode
  at all.

Sources, all secondary — forum threads and tool docs, no Microsoft
documentation of the frame choice:
[videohelp](https://forum.videohelp.com/threads/371019-COVER-ART-on-MKV-file-is-not-showing-only-THUMBNAIL-is-showing),
[shark007](https://shark007.net/forum/Thread-Cover-art-for-MKV-files-not-working),
[SageThumbs](https://sagethumbs.lunarwerx.com/formats/mkv/),
[elevenforum](https://www.elevenforum.com/t/mkv-thumbnail-in-explorer.6222/),
[zvidlib #502](https://github.com/lsegal/zvidlib/issues/502).

## Step 1 — measure before changing anything

No code until we know what Explorer does with the files already on `I:`.

1. Probe the shell directly rather than by eye: a small throwaway script
   that calls `SHCreateItemFromParsingName` +
   `IShellItemImageFactory::GetImage` for `I:\Video\Ready\Amelie.mkv` and
   saves what comes back as a PNG. Compare it with `Amelie.jpg`.
2. Then look in Explorer (Extra large icons) at that same folder, and at a
   file with no sidecar, to see whether a thumbnail exists, whether it is
   a frame, and roughly how far in.
3. Record what thumbnail provider is registered for `.mkv`
   (`HKCR\.mkv\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}`) and
   whether the HEVC extension is installed.

Write the three answers into this file under `## Result`. They decide
Step 2, and if Explorer already shows a decent frame the human may well
close this as not worth doing.

## Step 2 — pick a route (decision, not code)

| Route | What it costs | What it buys |
| :- | :- | :- |
| **A. Third-party provider** — install Icaros/SageThumbs, point it at the embedded cover attachment, clear the thumbnail cache | One per-viewing-machine install; a step in `InstallTools.ps1` and a README section; no change to a single mkv | Poster in Explorer, from the attachment we already write. Nothing else in the pipeline moves |
| **B. Bake the poster into the video stream** — prepend poster frames so frame 0 really is the cover | Needs ffmpeg as a new tool dependency; the prepended segment must match the H.265 stream's parameters or the whole file is re-encoded; every subtitle and chapter timestamp shifts by the inserted duration; the poster is visible on playback | Works in any player that grabs an early frame — *if* the grabber takes frame 0, which is exactly what is not documented |
| **C. MP4 output with `covr` cover art** | mp4 cannot carry the VobSub bitmap tracks, so `-ReplaceBitmapSubs` becomes mandatory and the original subtitles are lost; a second container to maintain | Explorer thumbnail with no decode and no per-machine install |

Recommendation: **A**, unless Step 1 shows no provider can be made to
work. B is a lot of fragile machinery for an undocumented frame choice,
and it degrades the file itself to fix a file manager. C trades subtitle
tracks for an icon.

## Step 3 — implement the chosen route

Only A is specified here, since it is the recommendation; B or C gets its
own planning pass if the human picks one.

1. `Scripts/InstallTools.ps1`: add the thumbnail provider as an optional
   winget install with its own `-Skip…` flag, matching how the other five
   tools are handled.
2. Set the "use embedded cover art" option and clear the thumbnail cache
   as part of that step, or document it where the install happens if it
   cannot be set from a script.
3. `README.md`: a short section under the tool table saying what Explorer
   does and does not read, and that the cover attachment `ConvertNext.ps1`
   already writes is what the provider picks up.
4. Unit tests: `InstallTools.ps1` has no test harness today, so this route
   adds no testable logic. If the route chosen turns out to touch poster
   handling in `ConvertNext.ps1`, it needs tests, and setting one up is
   part of that work.

## Open questions for the human

1. **Which route**, A, B or C — see the table. Needed before Step 3.
2. **Where do you actually see the wrong icon?** Explorer only, or some
   other app (a TV's media browser, a phone app)? A third-party Explorer
   provider fixes nothing outside Explorer, and that changes the answer to
   question 1.
3. **Is a visible poster at the start of playback acceptable?** Route B
   means the cover is on screen for a moment every time the file plays.
   If that is a no, B is out whatever else it buys.
