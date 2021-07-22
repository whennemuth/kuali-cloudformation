package org.bu.jenkins.active_choices.dao;

import java.util.List;

/**
 * Base class from which to implement various methods for acquiring docker output/info
 * 
 * @author wrh
 *
 */
public abstract class AbstractDockerDAO {

	/**
	 * Get a list of all docker images in the private repository, only including tags if they are explicit and not a default.
	 * @return
	 */
	public abstract List<String> getImages();
}