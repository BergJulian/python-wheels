repo="$PWD"
base="$repo/ns-3"

section ---------------- install ----------------
export NS3_VERSION=3.46
export NS3_PYTHON_VERSION=3.11

run apt-get update
run apt-get install -y --no-install-recommends \
        bzip2 \
        cmake \
        curl \
        g++-11 \
        git \
        libclang-dev \
        llvm-dev \
        make \
        ninja-build \
        patch \
        patchelf \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        qtbase5-dev \
        zip \
        && true


# 3.46
ns3_download_sha1=15f7e24e0e63ad64c0a65cef2724a71ef9443447

section ---------------- download ----------------
workdir /opt
run curl -L -o ns-3.tar.bz2 https://www.nsnam.org/releases/ns-$NS3_VERSION.tar.bz2
runsh "echo '${ns3_download_sha1} ns-3.tar.bz2' | sha1sum -c"
run mkdir ns-3 && tar xjf ns-3.tar.bz2 --strip-components 1 -C ns-3

section ---------------- build ns-3 ----------------
workdir /opt/ns-3
run mkdir build
workdir /opt/ns-3/build
run cmake -G Ninja \
	-DCMAKE_CXX_COMPILER=/usr/bin/g++-11 \
	-DNS3_PYTHON_BINDINGS=ON \
	-DPYTHON_EXECUTABLE=/usr/bin/python${NS3_PYTHON_VERSION} \
	-DPYTHON_SITE_INSTALL_DIR=/ns-3-install/lib/python${NS3_PYTHON_VERSION}/site-packages \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/ns-3-install \
	..
run ninja
run ninja install

run mkdir -p /ns-3-install/lib/python${NS3_PYTHON_VERSION}/site-packages
run cp -a /opt/ns-3/build/bindings/python/ns \
    /ns-3-install/lib/python${NS3_PYTHON_VERSION}/site-packages/

run ls /opt/ns-3/build/bindings/python/ns

section ---------------- NetAnim ----------------
workdir /opt
run git clone -b netanim-3.109 https://gitlab.com/nsnam/netanim.git
run update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100
workdir /opt/netanim
run qmake NetAnim.pro
run make -j $(nproc)
run mkdir -p /ns-3-install/usr/local/bin
run cp NetAnim /ns-3-install/usr/local/bin/

section ---------------- python wheel ----------------
# Python version variable already set:
# NS3_PYTHON_VERSION=3.11

# where cmake installed the python package
SITE_PACKAGES="/ns-3-install/lib/python${NS3_PYTHON_VERSION}/site-packages"

# sanity-check: fail early if the built package isn't found
run sh -c "if [ ! -d \"${SITE_PACKAGES}/ns\" ]; then echo 'ERROR: built ns package not found at ${SITE_PACKAGES}/ns' && ls -la \"${SITE_PACKAGES}\" || true; exit 1; fi"

# prepare wheel build tree
run rm -rf /opt/ns
run mkdir -p /opt/ns
# copy the full installed package (this includes compiled extension .so files under ns/_/)
run cp -a "${SITE_PACKAGES}/ns" /opt/ns/

# copy the top-level setup.py from the repo so bdist_wheel knows metadata
run cp "$repo/ns-3/setup.py" /opt/ns/setup.py
# ensure __init__ (if repo kept it at repo/ns-3/__init__.py)
run cp "$repo/ns-3/__init__.py" /opt/ns/ns/__init__.py

# (Optional) confirm files are present (helpful for debugging)
run sh -c "echo '=== /opt/ns tree ===' && find /opt/ns -maxdepth 4 -type f -ls | sed -n '1,200p'"

workdir /opt/ns
# build wheel using the correct python
run /usr/bin/python${NS3_PYTHON_VERSION} setup.py bdist_wheel

# unpack and re-pack to normalize the wheel name if needed (this step is optional)
run python3 -m wheel unpack -d patch "dist/ns-${NS3_VERSION}-py3-none-any.whl"
# If you must adjust rpaths (patchelf) do it here on the copied .so files:
run set -eux; \
    for f in patch/ns-*/ns/_/**/*.so patch/ns-*/ns/_/*.so 2>/dev/null; do \
        echo "patchelf setting rpath for $f"; \
        patchelf --set-rpath '$ORIGIN' "$f" || true; \
    done

run mkdir -p dist2
run python3 -m wheel pack -d dist2 "patch/ns-${NS3_VERSION}"
asset_path="$base/ns-${NS3_VERSION}-py3-none-linux_x86_64.whl"
run cp "dist2/ns-${NS3_VERSION}-py3-none-any.whl" "$asset_path"

section ---------------- asset ----------------
asset "$asset_path"
