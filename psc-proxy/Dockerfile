FROM nginx:latest

# Create certificate directories
RUN mkdir -p /etc/nginx/certs/ca

# CA certificate
COPY certs/ca/psc-ca.crt /etc/nginx/certs/ca/psc-ca.crt

# Proxy certificate and key
COPY certs/psc-proxy.crt /etc/nginx/certs/psc-proxy.crt
COPY certs/psc-proxy.key /etc/nginx/certs/psc-proxy.key

# Nginx configuration - use ARG to select dev or prod
ARG NGINX_CONF=nginx.prod.conf
COPY ${NGINX_CONF} /etc/nginx/nginx.conf

# Expose Cloudflare-compatible HTTPS ports
EXPOSE 80
EXPOSE 443
EXPOSE 2053
EXPOSE 2083

CMD ["nginx", "-g", "daemon off;"]
