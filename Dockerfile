FROM archlinux:base-devel
ARG INTERNAL_CERT
ARG AGE_PASSPHRASE
ARG IDENTITIES=""

ENV USER dynamo
ENV UID 1000
ENV GID 1000

# Create user and setup permissions on /etc/sudoers
RUN useradd -m -s /bin/bash -U -u $UID $USER && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    chmod 0440 /etc/sudoers && \
    chmod g+w /etc/passwd

USER $UID
COPY --chown=${USER}:${USER} . /home/${USER}/dotfiles
WORKDIR /home/${USER}
RUN /home/${USER}/dotfiles/scripts/build_container.sh "${IDENTITIES}"
ENTRYPOINT [ "/usr/bin/fish" ]
