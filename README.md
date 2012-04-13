	IMPORTANT: IF YOU ARE GOING TO INTEGRATE OpenUDID INSIDE A (STATIC) LIBRARY,
	PLEASE MAKE SURE YOU REFACTOR THE OpenUDID CLASS WITH A PREFIX OF YOUR OWN,
	E.G. ACME_OpenUDID. THIS WILL AVOID CONFUSION BY DEVELOPERS WHO ARE ALSO
	USING OpenUDID IN THEIR OWN CODE. 

![image](http://appsfire.com/images/misc/OpenUDID_Industry_supporters.png)

####Who is behind SecureUDID
The project was initiated by Yann Lechelle (co-founder Appsfire) on 8/28/11

- https://github.com/ylechelle

####Master Branches & Contributors
- iOS / MacOS code: https://github.com/ylechelle/OpenUDID
- Android code: https://github.com/vieux/OpenUDID

Please browse this github projects to discover the many contributors (discussions, code, pull requests, alternative branches, etc…)

- https://github.com/ylechelle/OpenUDID/network
- https://github.com/ylechelle/OpenUDID/contributors
- https://github.com/ylechelle/OpenUDID/issues

####Usage

	#include "OpenUDID.h"
	NSString* openUDID = [OpenUDID value];

####Synopsis
OpenUDID is a drop-in replacement for the deprecated uniqueIdentifier property of the UIDevice class on iOS (a.k.a. UDID) and otherwise is an industry-friendly equivalent for iOS and Android.

The agenda for this community driven project is to:
- Provide a reliable proxy and replacement for a universal unique device identifier. That is, persistent and sufficiently unique, on a per device basis.
- NOT use an obvious other sensitive unique identifier (like the MAC address) to avoid further deprecation and to protect device-level privacy concerns
- Enable the same OpenUDID to be accessed by any app on the same device
- Supply open-source code to generate and access the OpenUDID, for iOS and  Android
- Incorporate, from the beginning, a system that will enable user opt-out to match Apple’s initial intent

####Context
If you’re not already familiar with UDID’s, it’s a critical tool for analytic or CRM purposes. A developer could use UDID’s as a means to track how much time a user spent in his free app before upgrading to the paid version. UDID’s are also helpful for tracking the source of a download when advertising on an ad network. This is a fairly universal need in a thriving ecosystem: developers need the traceability from clicks to downloads to ensure that they pay the right price for their promotion. Proper tracking and funnel conversion is what has made the web a better place, with healthy competition and quantifiable metrics.

In the wake of Apple’s decision to deprecate UDID, some ad networks have already introduced their own proprietary solutions. The main motivation here was to find a UDID replacement not owned by any single provider. It is easy to foresee a fragmented market where UDID management is operated by multiple providers with no cooperation between them. This open source initiative is to enable a better solution for thousands of other mobile app developers.

#####Version History
- August 2011: launch of the initiative
- Sept. 9 2011: v1.0 of the code meeting all requirements
- March. 25 2012: removing all traces of the offending call on iOS

####Contributions needed
Equivalent OpenUDID systems on Windows Mobile 7/8, Blackberry, Windows .Net, etc...