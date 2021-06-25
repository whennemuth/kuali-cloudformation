package org.bu.jenkins.active_choices.dao.cache;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.active_choices.model.AbstractAwsResource;

public class RdsSnapshotDAOCache extends BasicDAOCache {
	private Logger logger = LogManager.getLogger(RdsSnapshotDAOCache.class.getName());

	@Override
	protected void performCustomPreCachingAction(AbstractAwsResource resource, AbstractAwsResource cachedResource) {
		// Not implemented		
	}

	@Override
	protected Logger getLogger() {
		return logger;
	}

}