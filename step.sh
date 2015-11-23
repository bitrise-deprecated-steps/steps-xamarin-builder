#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ruby "${THIS_SCRIPTDIR}/step.rb" \
	-p "${xamarin_project}" \
	-c "${xamarin_configuration}" \
	-l "${xamarin_platform}" \
	-i "${is_clean_build}" \
	-x "${command}"
