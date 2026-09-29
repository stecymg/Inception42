all:
	@mkdir -p /home/smontgen/data/wordpress
	@mkdir -p /home/smontgen/data/mariadb
	@mkdir -p /home/smontgen/data/redis
	@docker-compose -f ./srcs/docker-compose.yml up -d --build

down:
	@docker-compose -f ./srcs/docker-compose.yml down

re: down all

.PHONY: all down re
