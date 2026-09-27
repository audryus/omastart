PLUGIN_ID := audryus.omastart
BAR_QML := BarWidget.qml
# Último diretório de log do quickshell (muda a cada restart do shell)
LATEST_LOG_DIR = $(shell ls -td /run/user/1000/quickshell/by-id/*/ 2>/dev/null | head -n 1)
LATEST_LOG = $(LATEST_LOG_DIR)log.log

.PHONY: journal

log:
	@if [ -f "$(LATEST_LOG)" ]; then \
		echo "-- $(LATEST_LOG) --"; \
		grep -E "$(PLUGIN_ID)|ReferenceError|WARN scene|ERROR" "$(LATEST_LOG)" | tail -n 50; \
	else \
		echo "log nao encontrado"; \
	fi

journal:
	journalctl --no-pager --since "today" 2>&1 | grep -E "omarchy-shell|$(PLUGIN_ID)|ReferenceError|WARN scene" | tail -n 50

validate:
	omarchy plugin validate .

rescan:
	omarchy-shell shell rescanPlugins

restart: 
	omarchy restart shell
