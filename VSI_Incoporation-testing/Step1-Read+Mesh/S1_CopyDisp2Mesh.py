from ufl import *
from dolfin import *
import numpy as np
import pandas as pd


temp = 0
file1name = 'disp_field_%i'%temp
file2name = 'specimen_%i'%temp

#meshdir='../mesh/gmsh/holes_5mm_L%ia'%temp
#meshfilename = '/test%i.xdmf'%temp
# meshdir='../mesh/gmsh/noholes_L%ia'%temp
# meshfilename = '/testa.xdmf'
meshdir = '.'
meshfilename = '/ShearWavy_6.25MMDisp_Amp_0.6_tet.xdmf'


# datadir='../result/filtered/20220211-no_holes/raw_data'
datadir = '.'
NumStepList = [1]#,2,3]

mesh=Mesh()

with XDMFFile(meshdir+meshfilename) as infile:
    infile.read(mesh)


V = VectorFunctionSpace(mesh, "CG", 1)
W = FunctionSpace(mesh, "Lagrange", 1)

# Define functions
u = Function(V) 

coordinate_data=pd.read_csv(datadir + '/node_pos.txt').to_numpy()[:,0:3]

displacement_data = [0]*len(NumStepList)
for count,tid in enumerate(NumStepList):
	displacement_data[count]=pd.read_csv(datadir + '/disp_'+str(tid)+'.txt').to_numpy()[:,0:3]


# print(dof_to_vertex_map(V))
# print(dof_to_vertex_map(W))
# d2v_vector = dof_to_vertex_map(V)
# random_Class = V.dofmap()
# print(dir(random_Class))
a = V.dofmap().tabulate_local_to_global_dofs()
# print(a)

# exit()
coordinates = mesh.coordinates()

num_coordinate_file,_=coordinate_data.shape
num_coordinate_mesh,_=coordinates.shape
print('num_coordinate in file =',num_coordinate_file)
print('num_coordinate in mesh=',num_coordinate_mesh)
#num_displacement_file,_=displacement_data.shape
#print('num_displacement in file =',num_displacement_file)

u_array=np.zeros((num_coordinate_mesh*3, len(NumStepList)))

for i in range(num_coordinate_mesh):
  X=coordinates[i]
  index=-1
  _dist = coordinate_data[:,:]-X*np.ones([num_coordinate_file, 1])
  _dist = np.linalg.norm(_dist,axis = 1)
  index = np.argmin(_dist)
  # print('i=',i,' index=',index,' X=',X,' coordinate_data=',coordinate_data[index,:])
  for count,tid in enumerate(NumStepList):
    u_array[i*3:i*3+3, count]=np.reshape(displacement_data[count][index,:],(-1))

file_1 = XDMFFile(mesh.mpi_comm(),datadir + '/'+file1name+'.xdmf')
file_2 = HDF5File(MPI.comm_world, datadir + '/'+file2name+'.h5', 'w')
file_2.write(u,'/mesh')
for count,tid in enumerate(NumStepList):
  u.vector().set_local(u_array[a, count])
  u.vector().apply("insert")



  # Save solution 
  file_1.write(u, tid)
  # #
  file_2.write(u,'/disp%i'%tid)

file_1.close()
file_2.close()

