FROM busybox:1.36.1
COPY index.html /www/index.html
USER 1000
CMD ["httpd","-f","-p","8080","-h","/www"]
