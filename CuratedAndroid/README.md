# Curated for Android

Plays the videos Curated downloaded on your Mac, with the same Automix, Top 15, category mixes,
Time Limit and watched history. The phone never talks to TikTok; it only syncs with the Mac.

## Install

1. On the phone: Settings → About phone → tap Build number 7 times, then turn on USB debugging in Developer options.
2. Plug the phone into the Mac and run `./install.sh` (`./install.sh --debug` for a faster unoptimized build).

Needs JDK 21 (`brew install openjdk@21`) and the Android SDK in `~/Library/Android/sdk`.

## Pair and sync

1. On the Mac: Curated → Settings → Phone Sync → turn on **Allow syncing with your phone**.
2. Click the antenna button at the bottom of the sidebar → **Pair a Phone**.
3. On the phone: tap the sync button, pick the Mac (or type the address shown on the Mac) and enter the code.

Sync runs over Wi-Fi when both are on the same network, or over USB after `adb reverse tcp:8765 tcp:8765`
(`install.sh` does this for you). Turn on **Sync automatically** to sync about once an hour on Wi-Fi while charging.

Each sync downloads new videos, removes ones the Mac deleted, and merges watched history both ways
(the newest change to each video wins).

## Sync API (served by the Mac, port 8765)

See `Curated/Sources/Curated/PhoneSync.swift` in the Mac project.
