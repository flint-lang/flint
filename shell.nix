{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-24.05") {} }:

pkgs.mkShellNoCC {
	packages = with pkgs; [
		llvm_18
		clang_18
		libcxx # c++ standard library
		gcc
		cmake
	];
	shellHook = ''
		export DEV_ENVIRONMENT="flint"
		export NIX_SHELL_PATH="$(pwd)"
		source ~/.bashrc

		alias build-flint="$NIX_SHELL_PATH/flint/"
		alias build-calculator="$NIX_SHELL_PATH/resources/calculator/build.sh"
		alias run-calculator="$NIX_SHELL_PATH/resources/calculator/calculator"
		alias build-tutorial="$NIX_SHELL_PATH/resources/tutorial/kaleidoscope/src/builder.sh"
		alias run-tutorial="$NIX_SHELL_PATH/resources/tutorial/kaleidoscope/src/main"
	'';
}
