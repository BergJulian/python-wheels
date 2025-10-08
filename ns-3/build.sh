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
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/ns-3-install \
	..
run ninja
run ninja install

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
run mkdir -p /opt/ns/ns/_/lib
run mkdir -p /opt/ns/ns/_/bin

# Copy ns-3 shared libraries (.so files)
run cp -r /ns-3-install/lib/*.so /opt/ns/ns/_/lib/ || true

# Copy binaries (optional, e.g., ns3, helpers, etc.)
run cp -r /ns-3-install/bin/* /opt/ns/ns/_/bin/ || true

# Copy Python site-packages (if bindings installed there)
run cp -r /ns-3-install/lib/python$NS3_PYTHON_VERSION/site-packages/ns/* /opt/ns/ns/ || true

run mkdir -p /opt/ns
run cp -r "$repo/ns-3/ns" /opt/ns/
run cp "$repo/ns-3/ns/setup.py" /opt/ns/

# Create correct Python site-packages directory and copy __init__.py
run mkdir -p /ns-3-install/lib/python$NS3_PYTHON_VERSION/site-packages/ns
run cp "$repo/ns-3/__init__.py" /ns-3-install/lib/python$NS3_PYTHON_VERSION/site-packages/ns/

for f in /opt/ns/ns/_/lib/*.so; do
    run patchelf --set-rpath '$ORIGIN' "$f" || true
done

for f in /opt/ns/ns/_/bin/*; do
    run patchelf --set-rpath '$ORIGIN/../lib' "$f" || true
done

workdir /opt/ns
PY_PATH="/usr/bin/python${NS3_PYTHON_VERSION}"
run $PY_PATH setup.py bdist_wheel
run python3 -m wheel unpack -d patch "dist/ns-$NS3_VERSION-py3-none-any.whl"

run mkdir dist2
run python3 -m wheel pack -d dist2 "patch/ns-$NS3_VERSION"

asset_path="$base/ns-$NS3_VERSION-py3-none-linux_x86_64.whl"
run cp "dist2/ns-$NS3_VERSION-py3-none-any.whl" "$asset_path"

section ---------------- asset ----------------
asset "$asset_path"
