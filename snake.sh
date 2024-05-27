#!/bin/bash
# Author           : Stanisław Rzeszut (s198318@student.pg.edu.pl)
# Created On       : 15.04.2024
# Last Modified By : Stanisław Rzeszut (s198318@student.pg.edu.pl)
# Last Modified On : 21.04.2024
# Version          : 1.0
#
# Description      :
# Gracz steruje wężem za pomocą klawiszy WSAD. Jabłka są generowane losowo
# na planszy. Po zebraniu jabłka, jego pozycja jest resetowana, a wąż wydłuża
# się o jeden kwadrat. Prędkość węża jest regulowana za pomocą zmiennej,
# która jest zwiększana po zebraniu każdego jabłka.
#
# Licensed under GPL (see /usr/share/common-licenses/GPL for more details
# or contact # the Free Software Foundation for a copy)

if [ ! -f "readchar1" ]; then
  cc -x c -o readchar1 - <<EOF
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <termios.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  bool last = true;
  double time = 0;
  char *c = mmap(NULL, sizeof(*c), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);

  while (++argv, --argc) {
    if (strncmp(*argv, "-t", 2) == 0) {
      time = atof(*argv + 2);
    } else if (strncmp(*argv, "-f", 2) == 0) {
      last = false;
    } else {
      fprintf(stderr, "Usage: %s [-t<ms>] [-first]\n", argv[0]);
      return 1;
    }
  }

  struct termios t_old, t_new;
  tcgetattr(STDIN_FILENO, &t_old);
  t_new = t_old;
  t_new.c_lflag &= ~(ECHO | ICANON);
  tcsetattr(STDIN_FILENO, TCSANOW, &t_new);

  if (time == 0) {
    *c = getchar();
  } else {
    pid_t pid = fork();
    if (pid < 0) {
      perror("fork");
      return 1;
    } else if (pid == 0) {
      while (true) {
        char t = getchar();
        *c = last || !*c ? t : *c;
      }
    } else {
      usleep(time * 1000);
      kill(pid, SIGKILL);
    }
  }

  if (*c == 0) {
    return 1;
  }

  tcsetattr(STDIN_FILENO, TCSANOW, &t_old);
  putchar(*c);
  munmap(c, sizeof(*c));

  return 0;
}
EOF
fi

TERM_WIDTH=$(tput cols)
TERM_HEIGHT=$(($(tput lines) - 1))
VERSION=$(grep '^# Version' "$0" | cut -d : -f 2 | cut -c 2-)

SCORE=0

# Snake positions
SNAKE_DIR="UP"
SNAKE_X=()
SNAKE_Y=()

# Apples positions
APPLE_X=()
APPLE_Y=()

# Snake head
SNAKE_X[0]=$((TERM_WIDTH / 2))
SNAKE_Y[0]=$((TERM_HEIGHT / 2))

# Check if snake intersects with apple
is_snake_in_apple() {
  if [ ${#APPLE_X[@]} -gt 0 ]; then
    for ((ia = 0; ia < ${#APPLE_X[@]}; ia++)); do
      for ((is = 0; is < ${#SNAKE_X[@]}; is++)); do
        if [ ${APPLE_X[ia]} -eq ${SNAKE_X[is]} ] && [ ${APPLE_Y[ia]} -eq ${SNAKE_Y[is]} ]; then
          if [ "$1" = "true" ]; then
            unset APPLE_X[ia]
            unset APPLE_Y[ia]
          fi
          return 0
        fi
      done
    done
  fi

  return 1
}

# Check if snake is dead (in wall/itself)
is_snake_dead() {
  if [ ${SNAKE_X[0]} -lt 0 ] || [ ${SNAKE_X[0]} -ge $TERM_WIDTH ] || [ ${SNAKE_Y[0]} -lt 0 ] || [ ${SNAKE_Y[0]} -ge $TERM_HEIGHT ]; then
    return 0
  fi

  if [ ${#SNAKE_X[@]} -gt 1 ]; then
    for ((i = 1; i < ${#SNAKE_X[@]}; i++)); do
      if [ ${SNAKE_X[0]} -eq ${SNAKE_X[i]} ] && [ ${SNAKE_Y[0]} -eq ${SNAKE_Y[i]} ]; then
        return 0
      fi
    done
  fi

  return 1
}

# Check if first apple is in valid position
is_apple_ok() {
  if [ ${#APPLE_X[@]} -gt 1 ]; then
    for ((i = 1; i < ${#APPLE_X[@]}; i++)); do
      if [ ${APPLE_X[0]} -eq ${APPLE_X[i]} ] && [ ${APPLE_Y[0]} -eq ${APPLE_Y[i]} ]; then
        return 1
      fi
    done
  fi

  return 0
}

# Generate new apple in random position
generate_apple() {
  APPLE_X=($(($RANDOM % TERM_WIDTH)) "${APPLE_X[@]}")
  APPLE_Y=($(($RANDOM % TERM_HEIGHT)) "${APPLE_Y[@]}")
  while ! is_apple_ok || is_snake_in_apple; do
    APPLE[0]=$(($RANDOM % TERM_WIDTH))
    APPLE[1]=$(($RANDOM % TERM_HEIGHT))
  done
}

# Delay between snake moves based on its length
get_delay() {
  local delay=$(((300 - (${#SNAKE_X[@]} - 1) * 10)))
  if [ $delay -lt 10 ]; then
    delay=10
  fi
  echo $delay
}

handle_input() {
  case $SNAKE_DIR in
  UP | DOWN)
    local multiplier=2
    ;;
  LEFT | RIGHT)
    local multiplier=1
    ;;
  esac

  # Read input
  case $(./readchar1 -t$(($(get_delay) * $multiplier))) in
  w)
    if [ $SNAKE_DIR != "DOWN" ] || [ ${#SNAKE[@]} -eq 1 ]; then
      SNAKE_DIR="UP"
    fi
    ;;
  s)
    if [ $SNAKE_DIR != "UP" ] || [ ${#SNAKE[@]} -eq 1 ]; then
      SNAKE_DIR="DOWN"
    fi
    ;;
  a)
    if [ $SNAKE_DIR != "RIGHT" ] || [ ${#SNAKE[@]} -eq 1 ]; then
      SNAKE_DIR="LEFT"
    fi
    ;;
  d)
    if [ $SNAKE_DIR != "LEFT" ] || [ ${#SNAKE[@]} -eq 1 ]; then
      SNAKE_DIR="RIGHT"
    fi
    ;;
  q)
    break
    ;;
  esac

  # Move snake
  SNAKE_X_LAST=${SNAKE_X[${#SNAKE_X[@]} - 1]}
  SNAKE_Y_LAST=${SNAKE_Y[${#SNAKE_Y[@]} - 1]}
  if [ ${#SNAKE_X[@]} -gt 1 ]; then
    SNAKE_X=(${SNAKE_X[0]} "${SNAKE_X[@]:0:${#SNAKE_X[@]}-1}")
    SNAKE_Y=(${SNAKE_Y[0]} "${SNAKE_Y[@]:0:${#SNAKE_Y[@]}-1}")
  fi

  case $SNAKE_DIR in
  UP)
    SNAKE_Y[0]=$((${SNAKE_Y[0]} - 1))
    ;;
  DOWN)
    SNAKE_Y[0]=$((${SNAKE_Y[0]} + 1))
    ;;
  LEFT)
    SNAKE_X[0]=$((${SNAKE_X[0]} - 1))
    ;;
  RIGHT)
    SNAKE_X[0]=$((${SNAKE_X[0]} + 1))
    ;;
  esac

  # Check if snake eats apple
  if is_snake_in_apple true; then
    SCORE=$(($SCORE + 1))
    SNAKE_X+=($SNAKE_X_LAST)
    SNAKE_Y+=($SNAKE_Y_LAST)
    generate_apple
  fi
}

print_board() {
  clear

  for ((i = 0; i < ${#APPLE_X[@]}; i++)); do
    tput cup ${APPLE_Y[i]} ${APPLE_X[i]}
    echo -n "@"
  done

  for ((i = 0; i < ${#SNAKE_X[@]}; i++)); do
    tput cup ${SNAKE_Y[i]} ${SNAKE_X[i]}
    if [ $i -eq 0 ]; then
      if [ $SNAKE_DIR = "UP" ]; then
        echo -n "^"
      elif [ $SNAKE_DIR = "DOWN" ]; then
        echo -n "v"
      elif [ $SNAKE_DIR = "LEFT" ]; then
        echo -n "<"
      elif [ $SNAKE_DIR = "RIGHT" ]; then
        echo -n ">"
      fi
    else
      echo -n "#"
    fi
  done
}

print_info() {
  local text="SCORE: $SCORE  |  DELAY: $(get_delay)  |  CONTROLS: WSAD  |  PRESS Q TO QUIT"
  tput cup $(($TERM_HEIGHT + 1)) $((($TERM_WIDTH - ${#text}) / 2))
  echo -n $text
}

while getopts hva:s: opt; do
  case $opt in
  h)
    echo "Snake $VERSION"
    echo "Stanisław Rzeszut 198318"
    echo
    echo "Options:"
    echo "  -h  Display help"
    echo "  -v  Display version"
    echo "  -a  Apple count"
    echo "  -s  Snake length"
    exit 0
    ;;
  v)
    echo "Version: $VERSION"
    exit 0
    ;;
  a)
    MAX_APPLES=20
    if [ $OPTARG -lt 1 ] || [ $OPTARG -gt $MAX_APPLES ]; then
      echo "Apple count must be in range (1:$MAX_APPLES)"
      exit 1
    fi
    for ((i = 1; i < $OPTARG; i++)); do
      generate_apple
    done
    ;;
  s)
    MAX_SNAKE=$(($TERM_HEIGHT / 2))
    if [ $OPTARG -lt 1 ] || [ $OPTARG -gt $MAX_SNAKE ]; then
      echo "Snake length must be in range (1:$MAX_SNAKE)"
      exit 1
    fi
    for ((i = 1; i < $OPTARG; i++)); do
      SNAKE_X+=(${SNAKE_X[0]})
      SNAKE_Y+=($((${SNAKE_Y[0]} + $i)))
    done
    ;;
  *)
    echo "Invalid option: $opt"
    exit 1
    ;;
  esac
done

generate_apple
while true; do
  print_board
  print_info
  handle_input

  if is_snake_dead; then
    clear
    echo "GAME OVER! YOUR SCORE: $SCORE"
    break
  fi
done
