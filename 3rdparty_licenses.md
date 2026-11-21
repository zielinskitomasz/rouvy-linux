# Third-party components

Components this repository refers to. None of their code is copied into the repository.

| source | name | license type | license link |
| --- | --- | --- | --- |
| https://github.com/dockur/windows | dockur/windows (container image `dockurr/windows`) | MIT | https://github.com/dockur/windows/blob/master/license.md |
| https://github.com/actions/checkout | actions/checkout (CI only) | MIT | https://github.com/actions/checkout/blob/main/LICENSE |
| https://github.com/bats-core/bats-core | bats-core (test runner, installed from the distribution) | MIT | https://github.com/bats-core/bats-core/blob/master/LICENSE.md |

`rouvy build` and `rouvy update` also download proprietary software straight from its vendors to
your machine. It is not part of this repository and is not redistributed by it: Windows 11
(Microsoft), the Rouvy app (VirtualTraining s.r.o.) and, for Intel adapters, the Intel Wireless
Bluetooth driver (Intel). Their own licence terms apply.
