#!/usr/bin/env python3
"""Prevent shipping a redesigned Insights view that is not reachable from the tab bar.

The earlier premium Insights work compiled successfully while the tab root
continued to launch the legacy Recovery page. Keep this release invariant
visible in CI without requiring live HealthKit data or screenshot matching.
"""
from pathlib import Path

root = Path("ATHLTH/Views/ProductRootTabView.swift").read_text(encoding="utf-8")
insights = Path("ATHLTH/Insights/ATHLTHInsightsView.swift").read_text(encoding="utf-8")
sections = Path("ATHLTH/Insights/ATHLTHInsightsPremiumSections.swift").read_text(encoding="utf-8")

product_start = root.index("struct ProductRootTabView: View")
tab_view_start = root.index("TabView(selection: $selectedTab)", product_start)
insights_tab_end = root.index(".tag(2)", tab_view_start)
tab_wiring = root[tab_view_start:insights_tab_end][-850:]

if "ATHLTHInsightsView(" not in tab_wiring:
    raise SystemExit("Insights tab must open ATHLTHInsightsView, not the legacy recovery screen")
if "ATHLTHRecoveryView(" in tab_wiring:
    raise SystemExit("The recovery detail page cannot be the root Insights tab")
if "isActive: selectedTab == 2" not in tab_wiring:
    raise SystemExit("Insights should load active Health data only when its tab is selected")
if "ATHLTHInsightsNavigation(selection: $selectedSection)" not in insights:
    raise SystemExit("The premium Insights view must render its section selector")
if "case overview, health, training, development" not in sections:
    raise SystemExit("The four approved Insights sections must remain available")
if "ATHLTHRecoveryView(" in insights:
    raise SystemExit("Old Recovery screens must no longer be reachable from premium Insights")
if "ATHLTHDailyWellbeingSummaryCard(" not in insights:
    raise SystemExit("Insights Overview must show the athlete's actual daily answers")
if "ATHLTHDailyWellbeingTrendCard(" not in insights:
    raise SystemExit("Insights Trends must show self-reported 7/30-day history")
if "RecoverySorenessLogView(store: dailyCheckInStore)" not in insights:
    raise SystemExit("The daily check-in form must remain available inside Insights")

print("Insights tab root, four sections, self-report history and check-in sheet are wired.")
