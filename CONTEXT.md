# Kanso

A macOS menu bar app that quietly sorts new files in the user's watched folders onto shelves, and tells them only what they need to know.

## Language

### Files

**Shelf**:
A folder inside a watched folder's My Shelves where Kanso files items of one type (📄 Documents, 🪞 Duplicates). Where things live once sorted.
_Avoid_: Category, bucket, tray

**Watched folder**:
A folder whose top level Kanso sorts (Downloads, Desktop, Documents by default). Each one gets its own My Shelves, Manual Shelves and Recents once Kanso first sorts something there.
_Avoid_: Root, tracked folder, shelf, location

**Manual Shelves**:
The folder in a watched folder that belongs to the user; Kanso never moves anything into or out of it.
_Avoid_: Manual library, my folders

**Tray**:
A temporary holding place for things the user is carrying (files, links, snippets dropped onto the island) until they decide what to do with them; "Organize" files them onto shelves.
_Avoid_: Shelf, basket, stash, drop zone

**Provably spent**:
A file whose purpose has verifiably been fulfilled (an installer whose app is installed); the only kind of file Kanso moves to the Trash on its own.
_Avoid_: Junk, unneeded, redundant

### Telling the user

**Island**:
Kanso's one surface for things that happen while you're elsewhere. On a notch screen it's black and grows out of the notch; on a screen without one it's a Liquid Glass capsule just below the menu bar, present only while there's something to show. It always appears on the screen you're working on.
_Avoid_: Toast, notification, banner, HUD

**Below-the-notch mode**:
The island drawn as a floating Liquid Glass capsule under the menu bar on every screen, used when the user prefers it or another app occupies the notch.
_Avoid_: Independent mode, notch-free version, floating mode

**Compact island**:
The island's resting notice: one morphing icon and one line of text, never taking focus.
_Avoid_: Mini toast, pill

**Expanded island**:
The island after a dwell, click or the island shortcut: the notice's details, its actions and the ask field. With no notice showing, it opens in its overview state.
_Avoid_: Popover, panel, drawer

**Quick settings**:
The popover under Kanso's menu bar icon, for configuring Kanso (switches, folders, features), never for showing activity or stats.
_Avoid_: Extended view, menu, dashboard

**Ask field**:
The natural-language input at the bottom of the expanded island.
_Avoid_: Chat, command bar, prompt box

**Silent sort**:
A sort that shows nothing in the moment; it's only visible afterwards in the island's done list and in Recents.
_Avoid_: Quiet mode, background sort
