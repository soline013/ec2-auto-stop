#!/bin/bash

# ─────────────────────────────────────────
# setup-docker.sh
# Docker 및 Docker Compose 설치 스크립트
# 지원 OS: Ubuntu, Debian, Amazon Linux 2, CentOS/RHEL
# ─────────────────────────────────────────

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# OS 감지
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        log_error "지원하지 않는 OS입니다."
        exit 1
    fi

    log_info "감지된 OS: $OS $VERSION"
}

# root가 아니면 sudo로 재실행
check_root() {
    if [[ $EUID -ne 0 ]]; then
        exec sudo bash "$0"
    fi
}

# 기존 Docker 제거
remove_old_docker() {
    log_info "기존 Docker 패키지 제거 중..."

    case $OS in
        ubuntu|debian)
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            ;;
        centos|rhel|fedora|amzn)
            yum remove -y docker docker-client docker-client-latest docker-common \
                docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            ;;
    esac
}

# 필수 패키지 설치
install_prerequisites() {
    log_info "필수 패키지 설치 중..."

    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            ;;
        centos|rhel|fedora)
            yum install -y yum-utils device-mapper-persistent-data lvm2
            ;;
        amzn)
            yum install -y yum-utils
            ;;
    esac
}

# Docker 리포지토리 설정
setup_docker_repo() {
    log_info "Docker 리포지토리 설정 중..."

    case $OS in
        ubuntu)
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            ;;
        debian)
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            ;;
        centos|rhel)
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            ;;
        fedora)
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            ;;
        amzn)
            # Amazon Linux 2는 amazon-linux-extras 사용
            log_info "Amazon Linux 2 감지 - amazon-linux-extras 사용"
            ;;
    esac
}

# Docker 설치
install_docker() {
    log_info "Docker Engine 설치 중..."

    case $OS in
        ubuntu|debian)
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora)
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        amzn)
            amazon-linux-extras install docker -y
            ;;
    esac
}

# Docker Compose 설치 (standalone - Amazon Linux용)
install_docker_compose_standalone() {
    log_info "Docker Compose (standalone) 설치 중..."

    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

    if [ -z "$COMPOSE_VERSION" ]; then
        COMPOSE_VERSION="v2.24.5"
        log_warn "최신 버전 확인 실패, 기본 버전 사용: $COMPOSE_VERSION"
    fi

    log_info "Docker Compose 버전: $COMPOSE_VERSION"

    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
        -o /usr/local/bin/docker-compose

    chmod +x /usr/local/bin/docker-compose

    # 심볼릭 링크 생성
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
}

# Docker 서비스 시작 및 활성화
start_docker_service() {
    log_info "Docker 서비스 시작 및 활성화..."

    systemctl start docker
    systemctl enable docker

    log_info "Docker 서비스 상태:"
    systemctl status docker --no-pager || true
}

# 현재 사용자를 docker 그룹에 추가
add_user_to_docker_group() {
    local CURRENT_USER="${SUDO_USER:-$USER}"

    if [ "$CURRENT_USER" != "root" ]; then
        log_info "사용자 '$CURRENT_USER'를 docker 그룹에 추가 중..."
        usermod -aG docker "$CURRENT_USER"
        log_warn "변경 사항 적용을 위해 로그아웃 후 다시 로그인하세요."
    fi
}

# 설치 확인
verify_installation() {
    log_info "설치 확인 중..."

    echo ""
    echo "=========================================="
    echo "Docker 버전:"
    docker --version
    echo ""

    echo "Docker Compose 버전:"
    if command -v docker-compose &> /dev/null; then
        docker-compose --version
    fi

    if docker compose version &> /dev/null; then
        docker compose version
    fi
    echo "=========================================="
    echo ""
}

# Hello World 테스트
run_hello_world() {
    log_info "Docker Hello World 테스트 실행..."
    docker run --rm hello-world
}

# 메인 실행
main() {
    echo ""
    echo "=========================================="
    echo "   Docker & Docker Compose 설치 스크립트"
    echo "=========================================="
    echo ""

    check_root
    detect_os
    remove_old_docker
    install_prerequisites
    setup_docker_repo
    install_docker

    # Amazon Linux는 standalone compose 설치
    if [ "$OS" = "amzn" ]; then
        install_docker_compose_standalone
    fi

    start_docker_service
    add_user_to_docker_group
    verify_installation

    echo ""
    log_info "설치가 완료되었습니다!"
    echo ""
    echo "사용 방법:"
    echo "  docker run hello-world          # 테스트"
    echo "  docker compose up -d            # Compose 실행 (plugin)"
    echo "  docker-compose up -d            # Compose 실행 (standalone)"
    echo ""

    read -p "Hello World 테스트를 실행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_hello_world
    fi
}

main "$@"
