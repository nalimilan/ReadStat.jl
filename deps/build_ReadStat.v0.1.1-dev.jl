using BinaryProvider # requires BinaryProvider 0.3.0 or later

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    ExecutableProduct(prefix, "readstat", :readstat),
    LibraryProduct(prefix, String["libreadstat"], :libreadstat),
]

# Download binaries from hosted location
bin_prefix = "https://github.com/davidanthoff/ReadStatBuilder/releases/download/v0.1.1-build.3"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    Linux(:aarch64, :glibc) => ("$bin_prefix/ReadStat.v0.1.1-dev.aarch64-linux-gnu.tar.gz", "3a670d3ebc6e7eb2ed4f228142adb1ab975f2d0fa9489037453e098c9a3717a5"),
    Linux(:aarch64, :musl) => ("$bin_prefix/ReadStat.v0.1.1-dev.aarch64-linux-musl.tar.gz", "03bcd9b7402739ba674881c9a9af731aa3ee8644d2050a07554c4a3ab3320ebe"),
    Linux(:armv7l, :glibc, :eabihf) => ("$bin_prefix/ReadStat.v0.1.1-dev.arm-linux-gnueabihf.tar.gz", "7255a92bf6b320499061a0478705df3960bb3cd39db259e53602e7d18cfa51e2"),
    Linux(:armv7l, :musl, :eabihf) => ("$bin_prefix/ReadStat.v0.1.1-dev.arm-linux-musleabihf.tar.gz", "6a2688f0dfbc1fd8912b494642e194d09a778356989f25793f8baaf1313e3b15"),
    Linux(:i686, :glibc) => ("$bin_prefix/ReadStat.v0.1.1-dev.i686-linux-gnu.tar.gz", "c969c3cda37aa9924b98abe86ddcc72dc6c9b59744d2983e930b8d4b604f4de6"),
    Linux(:i686, :musl) => ("$bin_prefix/ReadStat.v0.1.1-dev.i686-linux-musl.tar.gz", "89d42858955bdeed036c07856b8ebdd87d73bc60ad771e246d67195454c31319"),
    Windows(:i686) => ("$bin_prefix/ReadStat.v0.1.1-dev.i686-w64-mingw32.tar.gz", "9d4919bf033d67c72a7c2c10d91b3a021cddf1d33db64db449fd63c17e73c14c"),
    Linux(:powerpc64le, :glibc) => ("$bin_prefix/ReadStat.v0.1.1-dev.powerpc64le-linux-gnu.tar.gz", "b7ffcdbc6eab6cfb673f581403508722982ef935f556c25fc53b7102c138eae8"),
    MacOS(:x86_64) => ("$bin_prefix/ReadStat.v0.1.1-dev.x86_64-apple-darwin14.tar.gz", "653c06b1f5be334510bf29588c7c0a8c34ad9dcab60693858cbba05f3083944a"),
    Linux(:x86_64, :glibc) => ("$bin_prefix/ReadStat.v0.1.1-dev.x86_64-linux-gnu.tar.gz", "87b2b96614f61ecdc63af890d3ecd926374bb7403b084c1fedc5cfd14db5a6ce"),
    Linux(:x86_64, :musl) => ("$bin_prefix/ReadStat.v0.1.1-dev.x86_64-linux-musl.tar.gz", "b95c666cdef269c6994bc009c7d09ff21b688c395e7578bbe8f6d723aa919342"),
    FreeBSD(:x86_64) => ("$bin_prefix/ReadStat.v0.1.1-dev.x86_64-unknown-freebsd11.1.tar.gz", "b41746a4845db5a4b1732fcc8f5c13b464e425c4a0ab44161c76c26dd41507bf"),
    Windows(:x86_64) => ("$bin_prefix/ReadStat.v0.1.1-dev.x86_64-w64-mingw32.tar.gz", "576faea230119c7ea6590a802c4695961d88a7f3ea515ecc5e01e740fbb2354c"),
)

# Install unsatisfied or updated dependencies:
unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
if haskey(download_info, platform_key())
    url, tarball_hash = download_info[platform_key()]
    if unsatisfied || !isinstalled(url, tarball_hash; prefix=prefix)
        # Download and install binaries
        install(url, tarball_hash; prefix=prefix, force=true, verbose=verbose)
    end
elseif unsatisfied
    # If we don't have a BinaryProvider-compatible .tar.gz to download, complain.
    # Alternatively, you could attempt to install from a separate provider,
    # build from source or something even more ambitious here.
    error("Your platform $(triplet(platform_key())) is not supported by this package!")
end

# Write out a deps.jl file that will contain mappings for our products
write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
