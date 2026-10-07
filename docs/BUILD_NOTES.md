# Build notes

Der Container verwendet einen Multi-Stage-Build. HandBrake wird in einem sauberen Ubuntu-24.04-Builder kompiliert. Die finale Runtime basiert ebenfalls auf Ubuntu 24.04 und enthält nur die für GTK4, noVNC/VNC und AMD Mesa VA-API benötigten Laufzeitpakete.

Das vermeidet Konflikte mit speziellen GUI-Basisimages, insbesondere bei der Installation von systemd-Abhängigkeiten während des Builds.
