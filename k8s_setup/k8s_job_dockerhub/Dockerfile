# Use official Rocky 8 image
FROM rockylinux:8

# Install bash (just in case)
RUN yum -y install bash && yum clean all

# Set working directory
WORKDIR /app

# Add a simple script
RUN echo -e '#!/bin/bash\n\necho "Hi from Rocky 8 container!"\ncat /etc/os-release' > hello.sh
RUN chmod +x hello.sh

# Set default command
CMD ["./hello.sh"]
