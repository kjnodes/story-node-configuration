#!/bin/bash
set -e

KJ_STORY_VERSION='v0.13.0' # without the `v` prefix
KJ_STORY_COMMIT='daaa395' # from `story version` on https://github.com/piplabs/story/releases
KJ_GETH_VERSION='0.11.0' # without the `v` prefix
KJ_GETH_COMMIT='f650370' # from `geth --version` on https://github.com/piplabs/story-geth/releases
KJ_UPGRADE_HEIGHT='858000'
KJ_GO_VERSION='1.22.8'
KJ_COSMOVISOR_VERSION='v1.7.0'
KJ_CHAIN_ID='odyssey'


# Set up Cosmovisor environment variables.
export DAEMON_HOME="$HOME/.story/story"
export DAEMON_NAME='story'


# We map `uname -m` responses to GOARCH values.
KJ_GO_ARCH=''
case "$(uname -m)" in
	amd64|x86_64)
		KJ_GO_ARCH='amd64'
		;;
	i386)
		KJ_GO_ARCH='386'
		;;
	aarch64)
		KJ_GO_ARCH='arm64'
		;;
	armv6l)
		KJ_GO_ARCH='armv6l'
		;;
	*)
		echo "Unsupported architecture: $(uname -m)" >&2
		exit 1
		;;
esac


CHECK_POSITIONAL='y'
screen_main() {

	echo -e '\e[0m' >&2

	if [ "x$CHECK_POSITIONAL" == 'xy' ]; then
		CHECK_POSITIONAL=''
		case "$1" in
			'')
				# no-op
				;;
			init)
				screen_init
				exit 0
				;;
			upgrade)
				screen_upgrade
				exit 0
				;;
			restart)
				screen_restart
				exit 0
				;;
			logs)
				screen_logs
				exit 0
				;;
			snapshot)
				screen_snapshot
				exit 0
				;;
			monitor)
				screen_monitor
				exit 0
				;;
			remove_all)
				screen_remove_all
				exit 0
				;;
			*)
				echo "Received unexpected argument: $1" >&2
				exit 1
				;;
		esac
	fi

	STORY_VERSION_OUT=''
	STORY_COMMIT_OUT=''
	if [ -x "$HOME/.story/story/cosmovisor/current/bin/story" ]; then
		STORY_VERSION_OUT="$($HOME/.story/story/cosmovisor/current/bin/story version 2>&1 | grep -Ee '^Version' | cut -d' ' -f2- | tr -d ' ')"
		STORY_COMMIT_OUT="$($HOME/.story/story/cosmovisor/current/bin/story version 2>&1 | grep -Ee '^Git Commit' | cut -d' ' -f3- | tr -d ' ')"
	fi
	GETH_VERSION_OUT=''
	if [ -x '/usr/local/bin/geth' ]; then
		GETH_VERSION_OUT="$(/usr/local/bin/geth --version | cut -d' ' -f3)"
	fi

	if [ "$STORY_VERSION_OUT" ]; then
		echo -e "\e[1m\e[32mCurrently running Story consensus $STORY_VERSION_OUT-$STORY_COMMIT_OUT.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mDid not find a local Story consensus client.\e[0m" >&2
	fi
	if [ "$GETH_VERSION_OUT" ]; then
		echo -e "\e[1m\e[32mCurrently running Geth v$GETH_VERSION_OUT.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mDid not find a local Geth client.\e[0m" >&2
	fi
	echo '' >&2

	echo -e 'Select an option:\e[0m' >&2
	( [ "x$STORY_VERSION_OUT" != 'x' ] || [ "x$GETH_VERSION_OUT" != 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '1 - Initialize service\e[0m' >&2
	( [ "x$STORY_VERSION_OUT" == "xv${KJ_STORY_VERSION}-stable" ] && [ "x$GETH_VERSION_OUT" == "x${KJ_GETH_VERSION}-stable-${KJ_GETH_COMMIT}" ] ) && echo -ne '\033[0;90m' >&2
	echo -e '2 - Upgrade service\e[0m' >&2
	( [ "x$STORY_VERSION_OUT" == 'x' ] && [ "x$GETH_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '3 - Restart services\e[0m' >&2
	( [ "x$STORY_VERSION_OUT" == 'x' ] && [ "x$GETH_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '4 - Show service logs\e[0m' >&2
	( [ "x$STORY_VERSION_OUT" == 'x' ] && [ "x$GETH_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '5 - Reset local data to pruned snapshot\e[0m' >&2
	( [ "x$STORY_VERSION_OUT" == 'x' ] && [ "x$GETH_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '6 - Configure local monitoring solution\e[0m' >&2
	echo -e '9 - Remove service and data\e[0m' >&2
	echo -e '0 - Exit\e[0m' >&2
	read -e -p '  > Enter your choice: ' choice
	echo '' >&2

	case "$choice" in
		1)
			screen_init
			;;
		2)
			screen_upgrade
			;;
		3)
			screen_restart
			;;
		4)
			screen_logs
			;;
		5)
			screen_snapshot
			;;
		6)
			screen_monitor
			;;
		9)
			screen_remove_all
			;;
		0)
			exit 0
			;;
		*)
			echo 'Unrecognized choice. Expected an option number to be provided.' >&2
			screen_main
			;;
	esac

}


screen_init() {

	# Check whether services already exist, and abort if so.
	if systemctl list-unit-files -q story-testnet.service >/dev/null; then
		echo 'Found `story-testnet` service file already installed.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi
	if systemctl list-unit-files -q story-testnet-geth.service >/dev/null; then
		echo 'Found `story-testnet-geth` service file already installed.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi
	if [ -e '/usr/local/bin/story' ]; then
		echo 'Found pre-existing `story` binary.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi
	if [ -e '/usr/local/bin/geth' ]; then
		echo 'Found pre-existing `story` binary.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi
	if [ -d "$HOME/.story" ]; then
		echo 'Found pre-existing Story configuration/data.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi

	# Check if values are provided as flags.
	moniker=''
	snapshot_type=''
	OPTIND=1
	while getopts hvf: opt; do
		case $opt in
			m)
				moniker="$OPTARG"
				;;
			s)
				snapshot_type="$OPTARG"
				;;
			*)
				# ignore unknown flags
				;;
		esac
	done
	shift "$((OPTIND-1))"

	# Obtain usable values for later.
	[ "x$moniker" == 'x' ] && read -e -p '> Enter your moniker/name for the node: ' moniker
	[ "x$snapshot_type" == 'x' ] && read -e -p '> Select snapshot type (archive/pruned): ' snapshot_type
	case "$snapshot_type" in
		archive)
			KJ_SNAP_GETH=https://snapshots.kjnodes.com/story-testnet-archive/snapshot_latest_geth.tar.lz4
			KJ_SNAP_STORY=https://snapshots.kjnodes.com/story-testnet-archive/snapshot_latest.tar.lz4
			;;
		pruned)
			KJ_SNAP_GETH=https://snapshots.kjnodes.com/story-testnet/snapshot_latest_geth.tar.lz4
			KJ_SNAP_STORY=https://snapshots.kjnodes.com/story-testnet/snapshot_latest.tar.lz4
			;;
		*)
			echo 'Unrecognized choice. Expected "archive" or "pruned" to be provided.' >&2
			screen_main
			return 1
			;;
	esac

	# Update OS packages for sanity.
	echo -e '\e[1m\e[32mUpdating system packages...\e[0m' >&2
	sudo apt-get -qq update
	sudo apt-get -qqy upgrade

	# Install OS package dependencies.
	echo -e '\e[1m\e[32mInstalling system dependencies...\e[0m' >&2
	sudo apt-get -qqy install curl lz4 ccze

	# Set up Golang dependency.
	echo -e "\e[1m\e[32mSetting up Go${KJ_GO_VERSION}...\e[0m" >&2
	[ -f "/usr/local/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz" ] || sudo curl -sLo "/usr/local/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz" "https://go.dev/dl/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz"
	sudo rm -rf /usr/local/go && sudo tar -xzf "/usr/local/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz" -C /usr/local
	if ! [ -x /etc/profile.d/golang.sh ] || ! grep -Fxq 'export PATH=$PATH:/usr/local/go/bin' /etc/profile.d/golang.sh; then
		sudo tee /etc/profile.d/golang.sh <<- EOF > /dev/null
			#!/bin/sh
			export PATH=$PATH:/usr/local/go/bin
		EOF
		sudo chmod a+rx /etc/profile.d/golang.sh
		source /etc/profile.d/golang.sh
	else
		# in case we have a non-login shell! or the script is restarted right after installation.
		# and even if we have it already sourced, doesn't hurt to add it another time.
		export PATH=$PATH:/usr/local/go/bin
	fi
	if ! grep -Fxq 'export PATH=$PATH:$HOME/go/bin' "$HOME/.profile" ; then
		eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a "$HOME/.profile")
	else
		# in case we have a non-login shell! or the script is restarted right after installation.
		# and even if we have it already sourced, doesn't hurt to add it another time.
		export PATH=$PATH:$HOME/go/bin
 	fi

	# Install Cosmovisor.
	echo -e "\e[1m\e[32mInstalling Cosmovisor $KJ_COSMOVISOR_VERSION...\e[0m" >&2
	go install "cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@$KJ_COSMOVISOR_VERSION"

	# Prepare directories for downloads.
	mkdir -p "$HOME/.story/geth" "$HOME/.story/story"
	KJ_TMP_DIR="$(mktemp -dqt story.XXXXXXXXXX)"
	trap "rm -rf '$KJ_TMP_DIR'" EXIT # and always clean up after ourselves.

	# Download Story consensus binary.
	echo -e "\e[1m\e[32mDownloading Story consensus client v$KJ_STORY_VERSION...\e[0m" >&2
	curl -sLo "$KJ_TMP_DIR/story" "https://github.com/piplabs/story/releases/download/v${KJ_STORY_VERSION}/story-linux-${KJ_GO_ARCH}"
	cosmovisor init "$KJ_TMP_DIR/story"
	sudo ln -s "$DAEMON_HOME/cosmovisor/current/bin/story" /usr/local/bin/story # just a helper symlink when user runs `story` directly.

	# Download Story execution binary.
	echo -e "\e[1m\e[32mDownloading Story execution client v$KJ_GETH_VERSION...\e[0m" >&2
	curl -sLo "$KJ_TMP_DIR/geth" "https://github.com/piplabs/story-geth/releases/download/v${KJ_GETH_VERSION}/geth-linux-${KJ_GO_ARCH}"
	sudo mv "$KJ_TMP_DIR/geth" /usr/local/bin/geth
	sudo chown 0:0 /usr/local/bin/geth
	sudo chmod 755 /usr/local/bin/geth

	# Initialize the node.
	echo -e '\e[1m\e[32mInitializing Story consensus client data...\e[0m' >&2
	story init --moniker "$moniker" --network $KJ_CHAIN_ID
	sed -i -e 's|^seeds *=.*$|seeds = "3f472746f46493309650e5a033076689996c8881@story-testnet.rpc.kjnodes.com:26659"|' "$HOME/.story/story/config/config.toml"

	# Enable Prometheus metrics.
	sed -i -e "s|^prometheus *=.*$|prometheus = true|" "$HOME/.story/story/config/config.toml"

	# Create a copy of validator private key.
	if [ -f "$HOME/story_backup/priv_validator_key.json" ]; then
		echo -e '\e[1m\e[32mRestoring pre-existing copy of validator private key...\e[0m' >&2
		cp --archive "$HOME/story_backup/priv_validator_key.json" "$HOME/.story/story/config/priv_validator_key.json"
	else
		echo -e '\e[1m\e[32mCreating a copy of validator private key...\e[0m' >&2
		mkdir -p -m 700 "$HOME/story_backup"
		cp --archive "$HOME/.story/story/config/priv_validator_key.json" "$HOME/story_backup/priv_validator_key.json"
		echo "If this node is a validator, please back up $HOME/story_backup/priv_validator_key.json to a safe location!" >&2
	fi

	# Configure SystemD services.
	echo -e '\e[1m\e[32mConfiguring background services...\e[0m' >&2
	sudo tee /etc/systemd/system/story-testnet-geth.service <<- EOF > /dev/null
		[Unit]
		Description=Story Execution Client service
		After=network-online.target

		[Service]
		User=$USER
		WorkingDirectory=~
		ExecStart=/usr/local/bin/geth --$KJ_CHAIN_ID --syncmode full --http --ws --metrics --metrics.addr 0.0.0.0 --metrics.port 6060
		Restart=on-failure
		RestartSec=10
		LimitNOFILE=65535

		[Install]
		WantedBy=multi-user.target
	EOF
	sudo tee /etc/systemd/system/story-testnet.service <<- EOF > /dev/null
		[Unit]
		Description=story node service
		After=network-online.target

		[Service]
		User=$USER
		ExecStart=$(which cosmovisor) run run
		Restart=on-failure
		RestartSec=10
		LimitNOFILE=65535
		Environment="DAEMON_HOME=$HOME/.story/story"
		Environment="DAEMON_NAME=story"
		Environment="UNSAFE_SKIP_BACKUP=true"

		[Install]
		WantedBy=multi-user.target
	EOF
	sudo systemctl daemon-reload
	sudo systemctl enable story-testnet-geth.service
	sudo systemctl enable story-testnet.service

	# Download snapshot.
	echo -e '\e[1m\e[32mDownloading snapshots...\e[0m' >&2
	mv "$HOME/.story/story/data/priv_validator_state.json" "$HOME/.story/story/priv_validator_state.json"
	rm -rf "$HOME/.story/geth/{$KJ_CHAIN_ID}/geth/chaindata"
	rm -rf "$HOME/.story/story/data"
	curl -L "$KJ_SNAP_GETH" | tar -Ilz4 -xf - -C "$HOME/.story/geth"
	curl -L "$KJ_SNAP_STORY" | tar -Ilz4 -xf - -C "$HOME/.story/story"
	mv "$HOME/.story/story/priv_validator_state.json" "$HOME/.story/story/data/priv_validator_state.json"

	# Start services. It's a wrap!
	echo -e '\e[1m\e[32mStarting background services...\e[0m' >&2
	sudo systemctl start story-testnet-geth.service
	sudo systemctl start story-testnet.service

	screen_main

}


screen_upgrade() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q story-testnet.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi
	if ! systemctl list-unit-files -q story-testnet-geth.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet-geth` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi
	if ! [ -d "$HOME/.story" ]; then
		echo 'Aborting! Did not find Story configuration/data.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi

	# Update OS packages for sanity.
	echo -e '\e[1m\e[32mUpdating system packages...\e[0m' >&2
	sudo apt-get -qq update
	sudo apt-get -qqy upgrade

	# Set up Golang dependency.
	if [ "x$(/usr/local/go/bin/go version)" == "xgo version go${KJ_GO_VERSION} linux/${KJ_GO_ARCH}" ]; then
		echo -e "\e[1m\e[32mSkipping setting up Go${KJ_GO_VERSION}.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mSetting up Go${KJ_GO_VERSION}...\e[0m" >&2
		[ -f "/usr/local/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz" ] || sudo curl -sLo "/usr/local/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz" "https://go.dev/dl/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz"
		sudo rm -rf /usr/local/go && sudo tar -xzf "/usr/local/go${KJ_GO_VERSION}.linux-${KJ_GO_ARCH}.tar.gz" -C /usr/local
	fi
	if ! [ -x /etc/profile.d/golang.sh ] || ! grep -Fxq 'export PATH=$PATH:/usr/local/go/bin' /etc/profile.d/golang.sh; then
		sudo tee /etc/profile.d/golang.sh <<- EOF > /dev/null
			#!/bin/sh
			export PATH=$PATH:/usr/local/go/bin
		EOF
		sudo chmod a+rx /etc/profile.d/golang.sh
		source /etc/profile.d/golang.sh
	else
		# in case we have a non-login shell!
		# and even if we have it already sourced, doesn't hurt to add it another time.
		source /etc/profile.d/golang.sh
	fi
	if ! grep -Fxq 'export PATH=$PATH:$HOME/go/bin' "$HOME/.profile" ; then
		eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a "$HOME/.profile")
	else
		# in case we have a non-login shell! or the script is restarted right after installation.
		# and even if we have it already sourced, doesn't hurt to add it another time.
		export PATH=$PATH:$HOME/go/bin
 	fi

	# Install Cosmovisor.
	if [ "x$(cosmovisor version --cosmovisor-only 2>&1)" == "xcosmovisor version: $KJ_COSMOVISOR_VERSION" ]; then
		echo -e "\e[1m\e[32mSkipping installing Cosmovisor $KJ_COSMOVISOR_VERSION.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mInstalling Cosmovisor $KJ_COSMOVISOR_VERSION...\e[0m" >&2
		go install "cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@$KJ_COSMOVISOR_VERSION"
	fi

	# Prepare directories for downloads.
	KJ_TMP_DIR="$(mktemp -dqt story.XXXXXXXXXX)"
	trap "rm -rf '$KJ_TMP_DIR'" EXIT # and always clean up after ourselves.

	# Download Story consensus binary.
	if [ -x "$HOME/.story/story/cosmovisor/upgrades/$KJ_STORY_VERSION/bin/story" ] &&
			[ "x$($HOME/.story/story/cosmovisor/upgrades/$KJ_STORY_VERSION/bin/story version 2>&1 | grep -Ee '^Version' | cut -d' ' -f2- | tr -d ' ')" == "xv${KJ_STORY_VERSION}-stable" ] &&
			[ "x$($HOME/.story/story/cosmovisor/upgrades/$KJ_STORY_VERSION/bin/story version 2>&1 | grep -Ee '^Git Commit' | cut -d' ' -f3- | tr -d ' ')" == "x${KJ_STORY_COMMIT}" ]; then
		echo -e "\e[1m\e[32mSkipping downloading Story consensus client v$KJ_STORY_VERSION.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mDownloading Story consensus client v$KJ_STORY_VERSION...\e[0m" >&2
		curl -sLo "$KJ_TMP_DIR/story" "https://github.com/piplabs/story/releases/download/v${KJ_STORY_VERSION}/story-linux-${KJ_GO_ARCH}"
		echo -e '\e[1m\e[32mAdding upgrade to Cosmovisor...\e[0m' >&2
		cosmovisor add-upgrade "$KJ_STORY_VERSION" "$KJ_TMP_DIR/story" --upgrade-height "$KJ_UPGRADE_HEIGHT" --force
	fi

	# Download Story execution binary.
	if [ "x$(/usr/local/bin/geth --version | cut -d' ' -f3)" == "x${KJ_GETH_VERSION}-stable-${KJ_GETH_COMMIT}" ]; then
		echo -e "\e[1m\e[32mSkipping downloading Story execution client v$KJ_GETH_VERSION.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mDownloading Story execution client v$KJ_GETH_VERSION...\e[0m" >&2
		curl -sLo "$KJ_TMP_DIR/geth" "https://github.com/piplabs/story-geth/releases/download/v${KJ_GETH_VERSION}/geth-linux-${KJ_GO_ARCH}"
		sudo mv "$KJ_TMP_DIR/geth" /usr/local/bin/geth
		sudo chown 0:0 /usr/local/bin/geth
		sudo chmod 755 /usr/local/bin/geth
		echo -e '\e[1m\e[32mRestarting Story execution client...\e[0m' >&2
		sudo systemctl restart story-testnet-geth.service
	fi

	screen_main

}


screen_restart() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q story-testnet.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi
	if ! systemctl list-unit-files -q story-testnet-geth.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet-geth` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi

	sudo systemctl restart story-testnet.service story-testnet-geth.service

	echo 'Successfully restarted!' >&2

	screen_main

}


screen_logs() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q story-testnet.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi
	if ! systemctl list-unit-files -q story-testnet-geth.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet-geth` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi

	# Check if values are provided as flags.
	service=''
	OPTIND=1
	while getopts hvf: opt; do
		case $opt in
			s)
				service="$OPTARG"
				;;
			*)
				# ignore unknown flags
				;;
		esac
	done
	shift "$((OPTIND-1))"

	[ "x$service" == 'x' ] && read -e -p '> Select service for logs (story/geth): ' service
	case "$service" in
		story)
			(trap 'exit 0' INT; journalctl -f -ocat --no-pager -u story-testnet.service | ccze -A)
			;;
		geth)
			(trap 'exit 0' INT; journalctl -f -ocat --no-pager -u story-testnet-geth.service | ccze -A)
			;;
		both)
			(trap 'exit 0' INT; journalctl -f -ocat --no-pager -u story-testnet.service -u story-testnet-geth.service | ccze -A)
			;;
		*)
			echo 'Unrecognized choice. Expected "story" or "geth" to be provided.' >&2
			screen_main
			return 1
			;;
	esac

	screen_main

}


screen_snapshot() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q story-testnet.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi
	if ! systemctl list-unit-files -q story-testnet-geth.service >/dev/null; then
		echo 'Aborting! Did not find `story-testnet-geth` service file installed.' >&2
		echo 'Is Story actually running on this system?' >&2
		screen_main
		return 1
	fi

	echo '!!! THIS WILL REPLACE ALL NODE DATA WITH PRUNED SNAPSHOT' >&2
	read -e -p '!!! PLEASE CONFIRM THIS OPERATION (yes/no): ' really_remove
	echo '' >&2

	if [ "x$really_remove" != 'xyes' ]; then
		echo 'Cancelling.' >&2
		screen_main
		return 0
	fi

	echo -e "\e[1m\e[32mStopping services...\e[0m" >&2
	sudo systemctl stop story-testnet.service story-testnet-geth.service

	cp "$HOME/.story/story/data/priv_validator_state.json" "$HOME/.story/story/priv_validator_state.json.backup"

	echo -e "\e[1m\e[32mRemoving existing local data...\e[0m" >&2
	rm -rf "$HOME/.story/story/data" "$HOME/.story/geth/{$KJ_CHAIN_ID}/geth/chaindata"

	echo -e "\e[1m\e[32mDownloading latest available snapshot...\e[0m" >&2
	curl -L https://snapshots.kjnodes.com/story-testnet/snapshot_latest_geth.tar.lz4 | tar -Ilz4 -xf - -C "$HOME/.story/geth"
	curl -L https://snapshots.kjnodes.com/story-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C "$HOME/.story/story"

	mv "$HOME/.story/story/priv_validator_state.json.backup" "$HOME/.story/story/data/priv_validator_state.json"

	echo -e "\e[1m\e[32mStarting services...\e[0m" >&2
	sudo systemctl start story-testnet.service story-testnet-geth.service

	echo 'Successfully completed!' >&2

	screen_main

}


screen_monitor() {

	myip="$(curl -4s https://myipv4.addr.tools/plain)"
	if [ "x$myip" == 'x' ]; then
		echo 'Stopping! Unable to determine an IP address of the host.' >&2
		screen_main
		return 1
	fi
	echo -e "\e[1m\e[32mUsing $myip as the host IP address.\e[0m" >&2

	telegram_bot_token=''
	telegram_user_id=''
	echo -e "\e[1m\e[32mThis process expects you to have configured a Bot token from @botfather.\e[0m" >&2
	echo -e "\e[1m\e[32mPlease see the steps at https://core.telegram.org/bots#6-botfather if not.\e[0m" >&2
	read -e -p '> Enter your Telegram bot token: ' telegram_bot_token
	if [ "x$telegram_bot_token" == 'x' ]; then
		echo 'Aborting! Expected a token to be provided.' >&2
		screen_main
		return 1
	fi
	read -e -p '> Enter your Telegram user ID (from @userinfobot): ' telegram_user_id
	if [ "x$telegram_bot_token" == 'x' ]; then
		echo 'Aborting! Expected a user ID to be provided.' >&2
		screen_main
		return 1
	fi

	echo -e "\e[1m\e[32mEnsuring pre-requisites...\e[0m" >&2
	sudo apt-get -qqy install ca-certificates curl

	echo -e "\e[1m\e[32mAdding Docker keyring...\e[0m" >&2
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc

	echo -e "\e[1m\e[32mAdding Docker package repository...\e[0m" >&2
	sudo tee /etc/apt/sources.list.d/docker.list <<- EOF > /dev/null
		deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable
	EOF
	sudo apt-get -qq update

	echo -e "\e[1m\e[32mInstalling Docker packages...\e[0m" >&2
	sudo apt-get -qqy install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	echo -e "\e[1m\e[32mConfiguring Docker services...\e[0m" >&2
	sudo systemctl enable docker.service
	sudo systemctl enable containerd.service
	sudo systemctl start docker.service
	sudo systemctl start containerd.service

	if [ -d "$HOME/story-node-monitoring" ]; then
		echo -e "\e[1m\e[32mResetting the node-monitoring repository...\e[0m" >&2
		git -C "$HOME/story-node-monitoring" fetch --quiet origin +main:main
		git -C "$HOME/story-node-monitoring" reset --quiet --hard origin/main
	else
		echo -e "\e[1m\e[32mObtaining the node-monitoring repository...\e[0m" >&2
		git clone --quiet https://github.com/kjnodes/story-node-monitoring.git "$HOME/story-node-monitoring"
	fi

	echo -e "\e[1m\e[32mUpdating configuration files...\e[0m" >&2
	sed -i -e "s'YOUR_TELEGRAM_BOT_TOKEN'${telegram_bot_token}'" "$HOME/story-node-monitoring/prometheus/alert_manager/alertmanager.yml"
	sed -i -e "s'YOUR_TELEGRAM_USER_ID'${telegram_user_id}'" "$HOME/story-node-monitoring/prometheus/alert_manager/alertmanager.yml"
	sed -i -e "s'YOUR_NODE_IP:COMET_PORT'${myip}:26660'" "$HOME/story-node-monitoring/prometheus/prometheus.yml"
	sed -i -e "s'YOUR_NODE_IP:GETH_PORT'${myip}:6060'" "$HOME/story-node-monitoring/prometheus/prometheus.yml"

	echo -e "\e[1m\e[32mStarting services...\e[0m" >&2
	pushd "$HOME/story-node-monitoring" >/dev/null
	docker compose up --detach --force-recreate --pull always
	popd >/dev/null

	echo 'Successfully started!' >&2
	echo "You can open Grafana at http://${myip}:9999 with default credentials admin/admin." >&2

	screen_main

}


screen_remove_all() {

	if ! systemctl list-units -q story-testnet-geth.service | grep story-testnet-geth.service >/dev/null &&
			! [ -e '/etc/systemd/system/story-testnet-geth.service' ] &&
			! systemctl list-units -q story-testnet.service | grep story-testnet.service >/dev/null &&
			! [ -e '/etc/systemd/system/story-testnet.service' ] &&
			! [ -e '/usr/local/bin/geth' ] &&
			! [ -e '/usr/local/bin/story' ] &&
			! [ -e "$HOME/.story" ] &&
			! [ -e "$HOME/story-node-monitoring" ]; then
		echo 'Did not find anything to remove.' >&2
		screen_main
		return 0
	fi


	echo '!!! THIS WILL REMOVE ALL NODE SERVICES AND DATA' >&2
	read -e -p '!!! PLEASE CONFIRM THIS OPERATION (yes/no): ' really_remove
	echo '' >&2

	if [ "x$really_remove" != 'xyes' ]; then
		echo 'Cancelling.' >&2
		screen_main
		return 0
	fi

	if systemctl list-units -q story-testnet-geth.service | grep story-testnet-geth.service >/dev/null; then
		sudo systemctl disable story-testnet-geth.service
		sudo systemctl stop story-testnet-geth.service
	fi
	if [ -e '/etc/systemd/system/story-testnet-geth.service' ]; then
		sudo rm -v '/etc/systemd/system/story-testnet-geth.service'
		sudo systemctl daemon-reload
	fi
	if systemctl list-units -q story-testnet.service | grep story-testnet.service >/dev/null; then
		sudo systemctl disable story-testnet.service
		sudo systemctl stop story-testnet.service
	fi
	if [ -e '/etc/systemd/system/story-testnet.service' ]; then
		sudo rm -v '/etc/systemd/system/story-testnet.service'
		sudo systemctl daemon-reload
	fi

	[ -e '/usr/local/bin/geth' ] && sudo rm -v '/usr/local/bin/geth'
	[ -e '/usr/local/bin/story' ] && sudo rm -v '/usr/local/bin/story'

	[ -e "$HOME/.story" ] && rm -rf "$HOME/.story"
	
	if [ -e "$HOME/story-node-monitoring" ]; then
		pushd "$HOME/story-node-monitoring" >/dev/null
		docker compose down --volumes
		popd >/dev/null
		rm -rf "$HOME/story-node-monitoring"
	fi

	echo 'Successfully completed!' >&2

	screen_main

}


clear

echo '' >&2
echo '██╗  ██╗     ██╗███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗' >&2
echo '██║ ██╔╝     ██║████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝' >&2
echo '█████╔╝      ██║██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗' >&2
echo '██╔═██╗ ██   ██║██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║' >&2
echo '██║  ██╗╚█████╔╝██║ ╚████║╚██████╔╝██████╔╝███████╗███████║' >&2
echo '╚═╝  ╚═╝ ╚════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝' >&2
echo '' >&2
echo 'Website: https://kjnodes.com' >&2
echo 'Story services: https://services.kjnodes.com/testnet/story' >&2
echo 'Twitter: https://x.com/kjnodes' >&2
echo '' >&2
sleep 1

screen_main
