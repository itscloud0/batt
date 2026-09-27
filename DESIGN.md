---
name: Batt Thermal
description: Native Mac battery and system monitor
colors:
  graphite-surface: "#1F242E"
  flow-blue: "#639ED6"
  charging-green: "#34C759"
  low-battery-orange: "#FF9F0A"
  primary-text: "#F5F5F7"
  secondary-text: "#A8ABB1"
typography:
  battery:
    fontFamily: "SF Pro, system-ui"
    fontSize: "36pt"
    fontWeight: 600
  metric:
    fontFamily: "SF Pro, system-ui"
    fontSize: "14pt"
    fontWeight: 600
  detail:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11pt"
    fontWeight: 500
rounded:
  popover: "12pt"
spacing:
  unit: "4pt"
---

# Design System: Batt Thermal

## Overview

**Creative North Star: “The Mac power instrument.”** One compact menu-bar surface joins AlDente-like battery control with immediately useful system diagnostics. Battery and system each own a visibly separate region. State and meaning lead; ornament does not.

## Colors

The popover uses a graphite native surface. Blue marks power paths and battery level; green marks active charging, orange marks low battery. Secondary labels stay readable against graphite. The UI should not encode a charging state with color alone.

## Typography

Use the system font for native legibility. The battery percentage is 36 pt; system measurements are 14 pt with tabular digits; state and action labels are 11–13 pt. Every watt value includes a source or destination label and an approximation sign when derived.

## Layout

The main popover is 340×400 pt. Its 4 pt rhythm groups the 188 pt battery and flow region, a 40 pt action strip, and the system region with three named metrics and two process rows. A compact layout never removes the meaning of a value to save space.

## Elevation & Depth

The surface is flat. Thin dividers and the power-flow ribbon create hierarchy; no nested cards or decorative gradients.

## Shapes

Use native status-icon states and aspect-fitted SF Symbols. The flow has one source-to-destination path or a clean split/merge with no overlapping translucent strokes. The charge rail has a separate draggable limit marker.

## Components

The exact charge limit remains available from the rail label. Heat protection and display controls are direct actions. CPU, memory and disk measurements have distinct captions. Each featured app has a normal Quit action with confirmation; the list never implies it can force-quit.

## Do's and Don'ts

- Show `Adapter → Mac`, `To battery`, or `Battery → Mac` beside watt readings.
- Label CPU as load, RAM as memory used, SSD as space used.
- Show a reading-updating state when adapter and battery telemetry disagree.
- Never present a derived zero-watt system value as a measured fact.
