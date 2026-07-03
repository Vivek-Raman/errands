# Errands

Errands is a native iOS SwiftUI app for planning trips with multiple stops using public transit. Users can list destinations such as a market, library, cafe, or other errands, and the app helps turn those stops into a practical route with transit information.

## Goals

- Make it easy for users to enter, review, reorder, and manage multiple trip stops.
- Provide clear public transit routes between stops, including travel time and cost when available.
- Help users compare route options and understand the full trip before they leave.
- Use native Apple frameworks and platform conventions: SwiftUI for the interface, MapKit/CoreLocation for locations and routing, and Xcode as the primary build environment.
- Handle unavailable route, location, permission, and pricing data clearly so users know what the app can and cannot provide.
- Favor small, readable changes that move the app toward focused multi-stop transit planning.

## Build Notes

- The first build attempt only failed because this machine has iPhone 17 simulators, not iPhone 16. I’m rerunning against the installed iPhone 17 simulator to get real compile errors.
