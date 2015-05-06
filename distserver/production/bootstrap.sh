#!/bin/bash

# Bootstrap the EUPSForge software distribution install by:
#
#	* Installing EUPS
#	* Installing Anaconda Python distribution, if necessary
#	* Installing the eupsforge package
#	* Creating the environ.xxx scripts
#

set -e

#
# Note to developers: change these when the EUPS version we use changes
#

EUPS_VERSION=${EUPS_VERSION:-1.5.8}

EUPS_GITREV=${EUPS_GITREV:-""}
EUPS_GITREPO=${EUPS_GITREPO:-"https://github.com/RobertLuptonTheGood/eups.git"}
EUPS_TARURL=${EUPS_TARURL:-"https://github.com/RobertLuptonTheGood/eups/archive/$EUPS_VERSION.tar.gz"}

EUPS_PKGROOT=${EUPS_PKGROOT:-"http://lsst-web.ncsa.illinois.edu/~mjuric/eupsforge"}

STACK_HOME="$PWD"

BOOTSTRAP="bootstrap.sh" # the canonical name of this file on the server

cont_flag=false
batch_flag=false
help_flag=false
noop_flag=false

# Use system python to bootstrap unless otherwise specified
PYTHON="${PYTHON:-/usr/bin/python}"

while getopts cbhnP: optflag; do
	case $optflag in
		c)
			cont_flag=true
			;;
		b)
			batch_flag=true
			;;
		h)
			help_flag=true
			;;
		n)
			noop_flag=true
			;;
		P)
			PYTHON=$OPTARG
	esac
done

shift $((OPTIND - 1))

if [[ "$help_flag" = true ]]; then
	echo
	echo "usage: $(basename $0) [-b] [-f] [-h] [-n] [-P <path-to-python>]"
	echo " -b -- Run in batch mode.	Don't ask any questions and install all extra packages."
	echo " -c -- Attempt to continue a previously failed install."
	echo " -h -- Display this help message."
	echo " -n -- No-op. Go through the motions but echo commands instead of running them."
	echo " -P [PATH_TO_PYTHON] -- Use a specific python to bootstrap the stack."
	echo
	exit 0
fi

echo
echo "EUPSForge Bootstrap Script"
echo "=========================="
echo

# Don't make this fatal, it should still work for developers who are hacking their copy.

set +e

AMIDIFF=$(curl -L --silent $EUPS_PKGROOT/$BOOTSTRAP | diff --brief - $0)

if [[ $AMIDIFF = *differ ]]; then
	echo "!!! This script differs from the official version on the distribution server."
	echo "    If this is not intentional, get the current version from here:"
	echo "    $EUPS_PKGROOT/$BOOTSTRAP"
fi

set -e

##########	If no-op, prefix every install command with echo

if [[ "$noop_flag" = true ]]; then
	cmd="echo"
	echo "!!! -n flag specified, no install commands will be really executed"
else
	cmd=""
fi

##########	Refuse to run from a non-empty directory

if [[ "$cont_flag" = false ]]; then
	if [[ ! -z "$(ls)" && ! "$(ls)" == "$BOOTSTRAP" ]]; then
		echo "Please run this script from an empty directory. The EUPSForge software collection will be installed into it."
		exit -1;
	fi
fi

##########  Discuss the state of Git.

if true; then
	if hash git 2>/dev/null; then
		GITVERNUM=$(git --version | cut -d\  -f 3)
		GITVER=$(printf "%02d-%02d-%02d\n" $(echo "$GITVERNUM" | cut -d. -f1-3 | tr . ' '))
	fi

	if [[ $GITVER < "01-08-04" ]]; then
		if [[ "$batch_flag" = true ]]; then
			WITH_GIT=1
		else
			cat <<-EOF
			You need at least git 1.8.4 for use with EUPSForge. We can install one
			for you.

			The git package installed by this installer will be managed by
			EUPSForge's EUPS package manager, and will not replace or modify your
			system git (if any).

			EOF

			while true; do
				read -p "Would you like us to install git? " yn
				case $yn in
					[Yy]* )
						echo "Will install git."
						WITH_GIT=1
						break
						;;
					[Nn]* )
						echo "Okay install git and rerun the script."
						exit;
						break;
						;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		fi
	else
		echo "Detected $(git --version). OK."
	fi
	echo
fi


##########	Test/warn about Python versions, offer to get anaconda if too old

if true; then
	PYVEROK=$(python -c 'import sys; print("%i" % (sys.hexversion >= 0x02070000 and sys.hexversion < 0x03000000))')
	if [[ "$batch_flag" = true ]]; then
		WITH_ANACONDA=1
	else
		if [[ $PYVEROK != 1 ]]; then
			cat <<-EOF

			Much of the software in EUPSForge requires Python 2.7; you seem to have
			$(python -V 2>&1) on your path ($(which python)). Please set up a compatible
			python interpreter, prepend it to your PATH, and rerun this script.
			Alternatively, we can set up the Anaconda Python distribution for you.
			EOF
		fi

		cat <<-EOF
		Installing the Anaconda Python Distribution:

		If you want, we can install the Anaconda Python software distribution for
		you. Anaconda includes the Python interpreter and a myriad of commonly
		used Python packages (including numpy, scipy, matplotlib, and many others).
		For more information, see https://store.continuum.io/cshop/anaconda/.

		The Anaconda Python installed by this installer will be managed by
		EUPSForge's EUPS package manager, and will not replace or modify your
		system python. If you already have Anaconda (or a similar Python
		distribution), feel free to skip this step.

		EOF

		while true; do
		read -p "Would you like us to install Anaconda Python distribution (if unsure, say yes)? " yn
		case $yn in
			[Yy]* )
				WITH_ANACONDA=1
				break
				;;
			[Nn]* )
				if [[ $PYVEROK != 1 ]]; then
			echo
			echo "Thanks. After you install Python 2.7 and the required modules, rerun this script to"
			echo "continue the installation."
			echo
			exit
				fi
				break;
				;;
			* ) echo "Please answer yes or no.";;
		esac
		done
		echo
	fi
fi

##########	Check if the user has Anaconda with libm exposed (https://github.com/ContinuumIO/anaconda-issues/issues/182)

if [[ $WITH_ANACONDA != "1" ]]; then					# Are we going to install our anaconda?
	if python -V 2>&1 | grep -q Anaconda; then			# Is the user's python from Anaconda?
		LIBM="$(dirname $(dirname $(which python)))/lib/libm.so"
		if [[ -f "$LIBM" ]]; then				# Does it come with its own libm.so?

			echo
			echo
			echo "========================================================================="
			echo
			echo "We've detected you're using a version of the Anaconda Python Distribution"
			echo "that comes with its own instance of libm (the low-level math library):"
			echo
			echo "	$LIBM"
			echo
			echo "This will cause problems when compiling some EUPSForge (and other) codes (e.g.,"
			echo "see https://github.com/ContinuumIO/anaconda-issues/issues/182)."
			echo
			echo "To resolve this issue, upgrade your 'system' package to version 5.8-2"
			echo "or later by running:"
			echo
			echo "	conda update system"
			echo
			echo ", or upgrade Anaconda to 2.2.0 (or later)."
			echo
			echo "CAVEAT: If you decide to upgrade Anaconda, note that version 2.2.0 comes"
			echo "with IPython 3.0 (now called Jupyter). Notebooks written by Jupyter"
			echo "are not in a format that previous versions of IPython can read."
			echo

			exit -1
		fi
	fi
fi

##########	Install EUPS

if true; then
	if [[ ! -x "$PYTHON" ]]; then
		echo -n "Cannot find or execute '$PYTHON'. Please set the PYTHON environment variable or use the -P"
		echo " option to point to system Python 2 interpreter and rerun."
		exit -1;
	fi

	if [[ "$PYTHON" != "/usr/bin/python" ]]; then
		echo "Using python at $PYTHON to install EUPS"
	fi

	if [[ -z $EUPS_GITREV ]]; then
		echo -n "Installing EUPS (v$EUPS_VERSION)... "
	else
		echo -n "Installing EUPS (branch $EUPS_GITREV from $EUPS_GITREPO)..."
	fi

	(
		mkdir _build && cd _build
		if [[ -z $EUPS_GITREV ]]; then
			# Download tarball from github
			$cmd curl -L $EUPS_TARURL | tar xzvf -
			$cmd cd eups-$EUPS_VERSION
		else
			# Clone from git repository
			$cmd git clone "$EUPS_GITREPO"
			$cmd cd eups
			$cmd git checkout $EUPS_GITREV
		fi

		$cmd ./configure --prefix="$STACK_HOME"/eups --with-eups="$STACK_HOME" --with-python="$PYTHON"
		$cmd make install

	) > eupsbuild.log 2>&1 && echo " done." || { echo " FAILED."; echo "See log in eupsbuild.log"; exit -1; }

fi

##########	Source EUPS

set +e
$cmd source "$STACK_HOME/eups/bin/setups.sh"
set -e

##########	Download optional components (python)

if true; then
	if [[ $WITH_GIT = 1 ]]; then
		echo "Installing git ... "
		$cmd eups distrib install --repository="$EUPS_PKGROOT" git
		$cmd setup git
		CMD_SETUP_GIT='setup git'
	fi

	if [[ $WITH_ANACONDA = 1 ]]; then
		echo "Installing Anaconda Python Distribution ... "
		$cmd eups distrib install --repository="$EUPS_PKGROOT" anaconda
		$cmd setup anaconda
		CMD_SETUP_ANACONDA='setup anaconda'
	fi
fi

##########	Install the Basic Environment

if true; then
	echo "Installing the basic environment ... "
	$cmd eups distrib install --repository="$EUPS_PKGROOT" eupsforge
fi

##########	Create the environment loader scripts

function generate_loader_bash() {
	file_name=$1
	cat > $file_name <<-EOF
		# This script is intended to be used with bash to load the minimal EUPSForge environment
		# Usage: source $(basename $file_name)

		# If not already initialized, set STACK_HOME to the directory where this script is located
		if [ "x\${STACK_HOME}" = "x" ]; then
		   STACK_HOME="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
		fi

		# Bootstrap EUPS
		EUPS_DIR="\${STACK_HOME}/eups"
		source "\${EUPS_DIR}/bin/setups.sh"
		EUPS_PATH="\${STACK_HOME}"

		# Setup optional packages
		$CMD_SETUP_ANACONDA
		$CMD_SETUP_GIT

		# Setup minimal EUPSForge environment
		setup eupsforge
EOF
}

function generate_loader_csh() {
	file_name=$1
	cat > $file_name <<-EOF
		# This script is intended to be used with (t)csh to load the minimal EUPSForge environment
		# Usage: source $(basename $file_name)

		set sourced=(\$_)
		if ("\${sourced}" != "") then
		   # If not already initialized, set STACK_HOME to the directory where this script is located
		   set this_script = \${sourced[2]}
		   if ( ! \${?STACK_HOME} ) then
			  set STACK_HOME = \`dirname \${this_script}\`
			  set STACK_HOME = \`cd \${STACK_HOME} && pwd\`
		   endif

		   # Bootstrap EUPS
		   set EUPS_DIR = "\${STACK_HOME}/eups"
		   source "\${EUPS_DIR}/bin/setups.csh"
		   set EUPS_PATH = "\${STACK_HOME}"

		   # Setup optional packages
		   $CMD_SETUP_ANACONDA
		   $CMD_SETUP_GIT

		   # Setup minimal EUPSForge environment
		   setup eupsforge
		endif
EOF
}

function generate_loader_ksh() {
	file_name=$1
	cat > $file_name <<-EOF
		# This script is intended to be used with ksh to load the minimal EUPSForge environment
		# Usage: source $(basename $file_name)

		# If not already initialized, set STACK_HOME to the directory where this script is located
		if [ "x\${STACK_HOME}" = "x" ]; then
		   STACK_HOME="\$( cd "\$( dirname "\${.sh.file}" )" && pwd )"
		fi

		# Bootstrap EUPS
		EUPS_DIR="\${STACK_HOME}/eups"
		source "\${EUPS_DIR}/bin/setups.sh"
		EUPS_PATH="\${STACK_HOME}"

		# Setup optional packages
		$CMD_SETUP_ANACONDA
		$CMD_SETUP_GIT

		# Setup minimal EUPSForge environment
		setup eupsforge
EOF
}

function generate_loader_zsh() {
	file_name=$1
	cat > $file_name <<-EOF
		# This script is intended to be used with zsh to load the minimal EUPSForge environment
		# Usage: source $(basename $file_name)

		# If not already initialized, set STACK_HOME to the directory where this script is located
		if [[ -z \${STACK_HOME} ]]; then
		   STACK_HOME=`dirname "$0:A"`
		fi

		# Bootstrap EUPS
		EUPS_DIR="\${STACK_HOME}/eups"
		source "\${EUPS_DIR}/bin/setups.zsh"
		EUPS_PATH="\${STACK_HOME}"

		# Setup optional packages
		$CMD_SETUP_ANACONDA
		$CMD_SETUP_GIT

		# Setup minimal EUPSForge environment
		setup eupsforge
EOF
}

for sfx in bash ksh csh zsh; do
	generate_loader_$sfx $STACK_HOME/environ.$sfx
done

##########	Helpful message about what to do next

cat <<-EOF

	Bootstrap complete! To add the EUPSForge software collection
	to your environment type one of:

	        source "$STACK_HOME/environ.bash"  # for bash
	        source "$STACK_HOME/environ.csh"   # for csh
	        source "$STACK_HOME/environ.ksh"   # for ksh
	        source "$STACK_HOME/environ.zsh"   # for zsh

	as apropriate for your shell.

	Individual EUPSForge products may now be installed with the usual \`eups
	distrib install' command.  For example, to install the Large Survey Database
	product, use:

	        eups distrib install lsd

	.

	                                      Thanks!
	                                            -- Your Friendly EUPSForge Elves
	                                                 http://github.com/EUPSForge

EOF
