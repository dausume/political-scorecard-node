FROM nginx:latest

# Copy the NGINX configuration file to the container
COPY nginx.psc.conf /etc/nginx/nginx.conf

EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
