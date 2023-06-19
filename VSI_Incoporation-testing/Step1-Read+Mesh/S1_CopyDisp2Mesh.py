import os
from ufl import *
from dolfin import *
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

temp = 0
filename_disp = 'disp_field_%i'%temp
filename_specimen = 'specimen_%i'%temp

meshdir = '.'
meshfilename = '/sq-8mm_sin-per-4_sin-amp-2mm_tet.xdmf' # reading in .xdmf mesh file created in Step1_msh2xdmf.py which describes the original MATLAB .inp mesh in a mesh.io python mesh

datadir = '.'
TimeStep = [2]

mesh_py=Mesh() # create empty FEniCS mesh object

with XDMFFile(meshdir+meshfilename) as infile: # create 'infile', an XDMFFile object imported from 'meshfilename'
    infile.read(mesh_py) # read in data from .xdmf file to mesh object called infile (used to access geometry/connectivity info about the mesh) 

V = VectorFunctionSpace(mesh_py, "CG", 1) # create vector function space for 'mesh' composed of linear piece-wise continuous Lagrangian functions
W = FunctionSpace(mesh_py, "Lagrange", 1) # Create a scalar function space for 'mesh'composed of linear piece-wise continuous Lagrangian functions

u = Function(V) # initialize function object

X_node_Abaqus=pd.read_csv(datadir + '/X_061623_validationtest2.csv', header=None).to_numpy()[:,0:3] # make coordinate_data variable which contains node positions from ABAQUS .txt data
displacement_elem_Abaqus = [0]*len(TimeStep) # initialize 'displacement_data' as a zeros vector of dimension 1 by len(NumStepList) (currently yields a 1 by 1).

# Check geometries are the same between Abaqus output and mesh object from .inp file in Step1
check_pos = mesh_py.coordinates()
check_disp = u.compute_vertex_values(mesh_py)
filename_geom = "GeometryCheck.png"
if os.path.exists(filename_geom):
    os.remove(filename_geom)
fig, axs = plt.subplots(1, 2, figsize=(10, 5))
plt.xlabel("x (mm)")
plt.ylabel("y (mm)")
axs[0].scatter(X_node_Abaqus[:,0],X_node_Abaqus[:,1],marker=",",alpha=0.1,color='blue',label='From .txt ABAQUS results file')
axs[0].set_title('From .txt ABAQUS results file')
axs[1].scatter(check_pos[:,0],check_pos[:,1],marker=",",alpha=0.1,color='red',label='From .inp file')
axs[1].set_title('From .inp file')
plt.legend()
plt.savefig(filename_geom)
plt.close()

for count,tid in enumerate(TimeStep):
	# displacement_elem_ABAQUS[count]=pd.read_csv(datadir + '/disp_'+str(tid)+'.txt', header=None).to_numpy()[:,0:3]
  displacement_elem_Abaqus[count]=pd.read_csv(datadir + '/U_061623_validationtest_2.csv', header=None).to_numpy()[:,0:3]

DOF2VertexMap = pd.read_csv('dof2vertex.txt', header=None).to_numpy()[:,0:3] # Read in dof2vertex.txt map

X_node_mesh = mesh_py.coordinates()

num_nodes_csv,_= X_node_Abaqus.shape
num_nodes_mesh,_=X_node_mesh.shape
# print('num_nodes_csv =',num_nodes_csv)
# print('num_nodes_inp =',num_nodes_mesh)

u_array=np.zeros((num_nodes_mesh*3, len(TimeStep))) # create array (1 x num_coordinate in mesh) of 0's to preallocate
index_test = np.zeros(num_nodes_mesh)
if X_node_Abaqus.shape == X_node_mesh.shape:
  print("Abaqus output and 'mesh' have the same number of nodes")
  if np.max(np.linalg.norm(X_node_Abaqus-X_node_mesh))/X_node_Abaqus.shape[0] < 0.0001: # interpolate if nodes are far from each other
    print("WARNING: Nodal points or ordering may be different between mesh and Abaqus output.")
    print("WARNING: The average spacing between data and mesh nodes is",np.sum(np.linalg.norm(X_node_Abaqus-X_node_mesh))/X_node_Abaqus.shape[0])
    print("WARNING: The max spacing between data and mesh nodes is",np.max(np.linalg.norm(X_node_Abaqus-X_node_mesh))/X_node_Abaqus.shape[0])
    for i in range(num_nodes_mesh): # looping over all nodes in data 
      # Find nearest csv node for each node in 'mesh' made with .inp file
      X=X_node_mesh[i] # import coordinates for node i in 'mesh'
      index=-1
      _dist = X_node_Abaqus[:,:]-X*np.ones([num_nodes_csv, 1]) 
      _dist = np.linalg.norm(_dist,axis = 1) # calculating distance from X[i] to each node 
      index = np.argmin(_dist) # index of element located closest to the ith node
      index_test[i] = index
    node_shift = np.count_nonzero(index_test-np.linspace(0,num_nodes_mesh-1,num_nodes_mesh))
    if node_shift == 0:
      print("NOTE: Nodal points and nearest data node indexing were identical.")
    else:
      print("WARNING: ",node_shift," of the nodes will be interpolated.")
    for i in range(num_nodes_mesh): # looping over all nodes in data 
      # Write displacement data from nearest node to Python node
      for count,tid in enumerate(TimeStep):
        u_array[i*3:i*3+3, count] = np.reshape(displacement_elem_Abaqus[count][index,:],(-1))
  else:
    # Write displacement data from nearest node to Python node
    print("Nodes positions match between mesh and Abaqus output.")
    u_array[:, count] = np.reshape(displacement_elem_Abaqus[count][:,:],(-1))
else:
  print("Abaqus output and 'mesh' should have the same number of nodes. Please check that the input files.")

# Write .xdmf/.h5 files with 
file_1 = XDMFFile(mesh_py.mpi_comm(),datadir + '/'+filename_disp+'.xdmf')
file_2 = HDF5File(MPI.comm_world, datadir + '/'+filename_specimen+'.h5', 'w')
file_2.write(u,'/mesh')

for count,tid in enumerate(TimeStep):
  # Adding displacements to 'u'
  u.vector().set_local(u_array[DOF2VertexMap, count])
  u.vector().apply("insert")

  # Save solution to .xdmf/.h5
  file_1.write(u, tid)
  file_2.write(u,'/disp%i'%tid)

# Check u
print("The displacement field name is ",u)

file_1.close()
file_2.close()