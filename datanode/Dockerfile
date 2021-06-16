FROM fhirfactory/pegacorn-base-hadoop-nosh

HEALTHCHECK CMD curl -f http://localhost:9864/ || exit 1

ENV HDFS_CONF_dfs_datanode_data_dir=file:///hadoop/dfs/data
RUN mkdir -p /hadoop/dfs/data

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

COPY core-site.xml /opt/hadoop-3.3.0/etc/hadoop/core-site.xml

EXPOSE 9864

CMD ["/run.sh"]
