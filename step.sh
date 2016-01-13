#!/bin/bash

THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ruby "${THIS_SCRIPT_DIR}/step.rb" \
	-p "${xamarin_project}" \
	-c "${xamarin_configuration}" \
	-l "${xamarin_platform}" \
	-i "${is_clean_build}" \
	-e "${export_options_path}" \
	-f "${platform_filter}"
