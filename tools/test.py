"""Offline tests for BlinkPingMark: the addon runs in Lua 5.1 (lupa) against tools/wow_stub.lua.

    pip install lupa
    python tools/test.py
"""
import os
import sys
import unittest

from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load():
    lua = LuaRuntime(unpack_returned_tuples=True)
    with open(os.path.join(ROOT, "tools", "wow_stub.lua"), encoding="utf-8") as f:
        stub = lua.execute(f.read())
    with open(os.path.join(ROOT, "BlinkPingMark.lua"), encoding="utf-8") as f:
        src = f.read()
    ns = lua.table()
    chunk = lua.eval("loadstring")(src, "=BlinkPingMark.lua")
    chunk("BlinkPingMark", ns)
    stub.Fire("ADDON_LOADED", "BlinkPingMark")
    return lua, stub, ns.internals


class Base(unittest.TestCase):
    def setUp(self):
        self.lua, self.stub, self.I = load()
        self.db = self.I.db()

    # --- helpers
    def assertSame(self, a, b):
        # lupa hands out a new proxy for every table access, so compare identity on the Lua side
        self.assertTrue(self.lua.eval("rawequal")(a, b), "not the same Lua table")

    def click(self, button="LeftButton", x=None, y=None, dt=0.1):
        if x is not None:
            self.stub.cursor[1] = x
            self.stub.cursor[2] = y
        self.stub.time = self.stub.time + dt
        return self.stub.Click(button)

    def unit_frame(self, unit):
        f = self.lua.globals().CreateFrame("Button", None, self.lua.globals().UIParent)
        f.SetAttribute(f, "unit", unit)
        return f

    def hover(self, x, y):
        self.stub.cursor[1] = x
        self.stub.cursor[2] = y
        self.I.UpdateSelection()

    def wedge_macros(self, buttons, n):
        return [buttons[i].GetAttribute(buttons[i], "macrotext1") for i in range(1, n + 1)]


class Zones(Base):
    def test_instances(self):
        for inst, kind in [("party", "dungeon"), ("scenario", "dungeon"), ("raid", "raid"),
                           ("pvp", "battleground"), ("arena", "arena")]:
            self.stub.instance = inst
            self.assertEqual(self.I.ZoneKind(), kind)

    def test_city_and_world(self):
        self.stub.instance = "none"
        self.stub.map = 1453
        self.assertEqual(self.I.ZoneKind(), "city")
        self.stub.map = 1
        self.assertEqual(self.I.ZoneKind(), "world")
        self.stub.pvp = "sanctuary"
        self.assertEqual(self.I.ZoneKind(), "city")

    def test_zone_switch_blocks_the_run(self):
        self.db.zones.world = False
        self.stub.focus = None
        for _ in range(3):
            self.click()
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_group_only_applies_to_marks(self):
        self.stub.inGroup = False
        self.assertTrue(self.I.Allowed(False))
        self.assertFalse(self.I.Allowed(True))
        self.db.groupOnly = False
        self.assertTrue(self.I.Allowed(True))


class ClickRuns(Base):
    def test_three_clicks_open_the_ping_wheel(self):
        self.stub.focus = None  # the world
        self.click(); self.click()
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))
        self.click()
        self.assertTrue(self.I.wheel.IsShown(self.I.wheel))

    def test_a_pause_restarts_the_run(self):
        self.stub.focus = None
        self.click(); self.click()
        self.click(dt=1.0)
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))
        self.assertEqual(self.I.state().clicks, 1)

    def test_moving_restarts_the_run(self):
        self.stub.focus = None
        self.click(x=100, y=100); self.click()
        self.click(x=140, y=100)
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_other_ui_does_not_count(self):
        self.stub.focus = self.lua.globals().CreateFrame("Frame", None, self.lua.globals().UIParent)
        for _ in range(3):
            self.click()
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_double_click_setting(self):
        self.lua.globals().SlashCmdList.BLINKPINGMARK("clicks 2")
        self.assertEqual(self.db.clicks, 2)
        self.stub.focus = None
        self.click(); self.click()
        self.assertTrue(self.I.wheel.IsShown(self.I.wheel))

    def test_right_button_setting_swaps_the_buttons(self):
        self.lua.globals().SlashCmdList.BLINKPINGMARK("button right")
        self.assertEqual(self.db.button, "RightButton")
        self.assertEqual(self.I.MarkButton(), "LeftButton")
        self.stub.focus = None
        for _ in range(3):
            self.click("RightButton")
        self.assertTrue(self.I.wheel.IsShown(self.I.wheel))

    def test_no_wheel_in_combat(self):
        self.stub.combat = True
        self.stub.focus = None
        for _ in range(3):
            self.click()
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))
        self.assertTrue(any("combat" in e for e in self.stub.errors.values()))


class PingWheel(Base):
    def open_on_ground(self):
        self.stub.focus = None
        self.stub.cursor[1], self.stub.cursor[2] = 400, 300
        for _ in range(3):
            self.click()
        self.assertTrue(self.I.wheel.IsShown(self.I.wheel))

    def test_ground_macros_and_order(self):
        self.open_on_ground()
        # Blizzard's order by orderIndex: Attack 1, Warning 2, OnMyWay 3, Assist 4
        self.assertEqual(self.wedge_macros(self.I.buttons, 4),
                         ["/ping [@cursor] 1", "/ping [@cursor] 2", "/ping [@cursor] 3", "/ping [@cursor] 4"])
        self.assertFalse(self.I.wheel.sendOnWedge)
        cx, cy = self.I.wheel.GetCenter(self.I.wheel)
        self.assertEqual((cx, cy), (400, 300))

    def test_sectors_middle_and_outside(self):
        self.open_on_ground()
        b = self.I.buttons
        self.hover(400, 390)  # top
        self.assertSame(self.I.state().hover, b[1])
        self.hover(310, 300)  # left: counterclockwise from the top
        self.assertSame(self.I.state().hover, b[2])
        self.hover(400, 210)  # bottom
        self.assertSame(self.I.state().hover, b[3])
        self.hover(490, 300)  # right
        self.assertSame(self.I.state().hover, b[4])
        self.hover(405, 302)  # the middle
        self.assertEqual(self.I.state().hover, False)
        self.hover(400, 500)  # outside the ring
        self.assertIsNone(self.I.state().hover)

    def test_ground_ping_is_sent_from_the_middle(self):
        self.open_on_ground()
        b = self.I.buttons
        self.hover(400, 390)  # arm Attack
        self.assertFalse(b[1].IsMouseEnabled(b[1]))  # wedges do not take the click for ground pings
        self.assertFalse(self.I.send.IsMouseEnabled(self.I.send))
        self.hover(402, 300)  # back to the middle
        self.assertTrue(self.I.send.IsMouseEnabled(self.I.send))
        self.assertEqual(self.I.send.GetAttribute(self.I.send, "macrotext1"), "/ping [@cursor] 1")
        f = self.click()
        self.assertSame(f, self.I.send)
        self.assertEqual(list(self.stub.macros.values()), ["/ping [@cursor] 1"])
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_middle_with_nothing_armed_cancels(self):
        self.open_on_ground()
        self.hover(402, 300)
        self.click()
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))
        self.assertEqual(len(self.stub.macros), 0)

    def test_click_outside_closes(self):
        self.open_on_ground()
        self.click(x=900, y=900)
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_other_button_closes(self):
        self.open_on_ground()
        self.hover(400, 390)
        self.click("RightButton")
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))
        self.assertEqual(len(self.stub.macros), 0)

    def test_timeout_closes(self):
        self.open_on_ground()
        self.stub.time = self.stub.time + 7
        self.stub.Update(self.I.wheel)
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_unit_frame_pings_the_unit_on_the_wedge(self):
        self.stub.units.party1 = self.lua.table(guid="g-party1", name="Aldric")
        self.stub.focus = self.unit_frame("party1")
        self.stub.cursor[1], self.stub.cursor[2] = 400, 300
        for _ in range(3):
            self.click()
        self.assertTrue(self.I.wheel.IsShown(self.I.wheel))
        self.assertTrue(self.I.wheel.sendOnWedge)
        self.assertEqual(self.wedge_macros(self.I.buttons, 4)[1], "/ping [@party1] 2")
        self.hover(310, 300)  # Warning, on the left
        b = self.I.buttons
        self.assertTrue(b[2].IsMouseEnabled(b[2]))
        self.assertFalse(b[1].IsMouseEnabled(b[1]))
        self.click()
        self.assertEqual(list(self.stub.macros.values()), ["/ping [@party1] 2"])
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_world_unit_resolves_a_token(self):
        self.stub.units.mouseover = self.lua.table(guid="g-boar", name="Boar")
        self.stub.units.nameplate3 = self.lua.table(guid="g-boar", name="Boar")
        self.assertEqual(self.I.TokenFor("g-boar"), "nameplate3")
        self.stub.focus = None
        for _ in range(3):
            self.click()
        self.assertEqual(self.wedge_macros(self.I.buttons, 4)[0], "/ping [@nameplate3] 1")
        self.assertTrue(self.I.wheel.sendOnWedge)

    def test_world_unit_without_a_token_is_contextual(self):
        self.stub.units.mouseover = self.lua.table(guid="g-x", name="Stranger")
        self.stub.focus = None
        for _ in range(3):
            self.click()
        self.assertEqual(self.wedge_macros(self.I.buttons, 4)[0], "/ping 1")

    def test_quick_mode_sends_ground_pings_on_the_wedge(self):
        self.db.quick = True
        self.open_on_ground()
        self.assertTrue(self.I.wheel.sendOnWedge)
        self.hover(400, 390)
        self.click()
        self.assertEqual(list(self.stub.macros.values()), ["/ping [@cursor] 1"])

    def test_small_wheel_geometry(self):
        self.db.small = True
        self.open_on_ground()
        w, h = self.I.wheel.GetSize(self.I.wheel)
        self.assertEqual((w, h), (128, 128))
        self.hover(400, 345)  # 45 px up: inside the small ring
        self.assertSame(self.I.state().hover, self.I.buttons[1])


class MarkWheel(Base):
    def open_on(self, unit, icon=None, button="RightButton"):
        self.stub.units[unit] = self.lua.table(guid="g-" + unit, name=unit, icon=icon)
        self.stub.focus = self.unit_frame(unit)
        self.stub.cursor[1], self.stub.cursor[2] = 400, 300
        for _ in range(3):
            self.click(button)

    def test_opens_on_a_unit_frame_with_the_other_button(self):
        self.open_on("target")
        self.assertTrue(self.I.mark.IsShown(self.I.mark))
        self.assertEqual(self.wedge_macros(self.I.markButtons, 8)[7], "/tm [@target] 8")

    def test_not_on_the_world(self):
        self.stub.focus = None
        for _ in range(3):
            self.click("RightButton")
        self.assertFalse(self.I.mark.IsShown(self.I.mark))
        self.assertFalse(self.I.wheel.IsShown(self.I.wheel))

    def test_current_icon_clears(self):
        self.open_on("target", icon=5)
        macros = self.wedge_macros(self.I.markButtons, 8)
        self.assertEqual(macros[4], "/tm [@target] 0")
        self.assertEqual(macros[5], "/tm [@target] 6")

    def test_pick_skull(self):
        self.open_on("target")
        # 8 wedges counterclockwise from the top: Skull (8) is the last, 45 degrees clockwise from the top
        self.stub.cursor[1], self.stub.cursor[2] = 400 + 64, 300 + 64
        self.I.UpdateMark()
        self.assertEqual(self.I.state().markHover, 8)
        self.assertTrue(self.I.markButtons[8].IsMouseEnabled(self.I.markButtons[8]))
        self.click()
        self.assertEqual(list(self.stub.macros.values()), ["/tm [@target] 8"])
        self.assertFalse(self.I.mark.IsShown(self.I.mark))

    def test_middle_cancels(self):
        self.open_on("target")
        self.stub.cursor[1], self.stub.cursor[2] = 403, 300
        self.I.UpdateMark()
        self.click()
        self.assertFalse(self.I.mark.IsShown(self.I.mark))
        self.assertEqual(len(self.stub.macros), 0)

    def test_blizzard_menu_is_closed_during_the_run(self):
        self.open_on("target")
        self.assertGreaterEqual(self.stub.menusClosed, 3)

    def test_solo_blocks_marks_but_not_pings(self):
        self.stub.inGroup = False
        self.open_on("target")
        self.assertFalse(self.I.mark.IsShown(self.I.mark))
        self.stub.focus = None
        for _ in range(3):
            self.click("LeftButton")
        self.assertTrue(self.I.wheel.IsShown(self.I.wheel))

    def test_mark_wheel_off(self):
        self.db.mark = False
        self.open_on("target")
        self.assertFalse(self.I.mark.IsShown(self.I.mark))

    def test_not_in_combat(self):
        self.stub.combat = True
        self.open_on("target")
        self.assertFalse(self.I.mark.IsShown(self.I.mark))


class Settings(Base):
    def test_slash_opens_the_panel(self):
        self.lua.globals().SlashCmdList.BLINKPINGMARK("")
        self.assertEqual(self.stub.panelOpened, 1)

    def test_defaults_and_toggles(self):
        self.assertEqual(self.db.clicks, 3)
        self.assertEqual(self.db.button, "LeftButton")
        self.assertTrue(self.db.groupOnly)
        self.assertTrue(self.db.mark)
        cmd = self.lua.globals().SlashCmdList.BLINKPINGMARK
        cmd("quick"); self.assertTrue(self.db.quick)
        cmd("small"); self.assertTrue(self.db.small)
        cmd("mark"); self.assertFalse(self.db.mark)
        cmd("group"); self.assertFalse(self.db.groupOnly)
        cmd("interval 0.8"); self.assertAlmostEqual(self.db.interval, 0.8)

    def test_wedges_follow_blizzards_order(self):
        w = self.I.Wedges()
        self.assertEqual([w[i].kit for i in range(1, 5)], ["Attack", "Warning", "OnMyWay", "Assist"])
        self.assertEqual([w[i].number for i in range(1, 5)], ["1", "2", "3", "4"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
