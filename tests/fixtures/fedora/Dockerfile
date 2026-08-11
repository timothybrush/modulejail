# tests/fixtures/fedora/Dockerfile
# fedora:latest tracks the current stable Fedora, so CI always exercises the
# newest Fedora userland (dnf5, current package layout). Added after the
# Fedora packaging effort (upstream: @jforbes / Justin Forbes).
FROM fedora:latest
RUN dnf -y install ShellCheck findutils gawk diffutils && dnf clean all
COPY modulejail /usr/local/bin/modulejail
RUN chmod +x /usr/local/bin/modulejail
COPY tests/lib /tests/lib
WORKDIR /tests
CMD ["sh", "/tests/lib/run-in-fixture.sh", "fedora"]
