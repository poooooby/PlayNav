# 💾 Installation

[← Back to the README](../README.md)

1. Download the latest release from the [Releases](https://github.com/poooooby/PlayNav/releases)
   page.
2. Import it with the Gen1Recomp Mod Manager, or drop it in your mods folder.
3. Enable **NaviPlay**.
4. **For the 3DS art and text (optional):** open the mod in the launcher, choose
   **Imported files**, then **Choose file**. Pick your own decrypted **Pokémon Omega Ruby or
   Alpha Sapphire (USA)**: a card image (`.cci` / `.3ds`, trimmed or not) or a decrypted
   `.cia`. Without one, NaviPlay plays with its own art, sounds and words. NaviPlay checks each
   piece it uses as it unpacks them, and draws its own art for any piece your copy holds
   differently. On Gen1Recomp builds from before mod-checked imports (before 0.3.96), the
   launcher accepts only this exact Alpha Sapphire file:

   | | |
   |---|---|
   | **Format** | Decrypted `.cci` |
   | **Size** | 2,147,483,648 bytes (2 GiB) |
   | **MD5** | `0563f9dee1b95de32d579e40c20e2bfc` |

   The launcher keeps a private copy. The first time NaviPlay starts, its screen
   asks: **Begin extraction** unpacks the art, music, sound effects and text with a progress
   bar (a few seconds, in the background while you play), then tells you the copy can be
   removed under Imported files; **Use fallback assets** uses NaviPlay's own instead. Without a
   copy, or with the wrong one, the screen says so (**OR/AS ROM not found** / **Incorrect ROM
   added**) and offers the fallback assets; if you add the right copy later, NaviPlay offers
   it again on the next start.
